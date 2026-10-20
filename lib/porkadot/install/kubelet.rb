module Porkadot; module Install
  class KubeletList
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'kubelet')
    # Used by porkadot before secrets were merged into the assets tree.
    LEGACY_TEMPS = %w(.kubelet .default .default.kubelet).map { |d| File.join(Porkadot::Install::KUBE_TEMP, d) }
    ETCD_TEMP = '/opt/porkadot'
    ETCD_DATA_DIR = '/var/lib/etcd'
    # etcd's disaster recovery guide: covers a week of writes below 1500/s.
    # The restored revision then stays above every revision a client has
    # seen, and marking it compacted makes every watch list again.
    RESTORE_BUMP_REVISION = 1_000_000_000
    CONTAINERD_ENDPOINT = 'unix:///run/containerd/containerd.sock'
    # Restarted after a restore, apiservers first. They all run on masters.
    CONTROL_PLANE_CONTAINERS = ['kube-apiserver', 'kube-controller-manager', 'kube-scheduler']
    DEFAULT_RESTORE_TIMEOUT = 600
    POLL_INTERVAL = 5
    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :logger
    attr_reader :kubelets

    def initialize global_config
      @global_config = global_config
      @logger = global_config.logger
      @kubelets = {}
      global_config.nodes.each do |k, config|
        @kubelets[k] = Kubelet.new(config)
      end
    end

    def setup_containerd hosts: nil, force: false
      hosts = self.exec hosts: hosts
      on(hosts) do |host|
        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'setup-containerd.sh'))
        end
      end
    end

    def setup_default hosts: nil, force: false
      hosts = self.exec hosts: hosts
      on(hosts) do |host|
        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'setup-node.sh'))
        end
      end
    end

    def install hosts: nil, force: false
      hosts = self.exec hosts: hosts
      on(hosts) do |host|
        as user: 'root' do
          # install-deps.sh links the configured versions and downloads only
          # the missing ones, unless --force is given.
          deps = [File.join(KUBE_TEMP, 'install-deps.sh')]
          deps << '--force' if force
          execute(:bash, *deps)
          execute(:bash, File.join(KUBE_TEMP, 'install-pkgs.sh'))
          execute(:bash, File.join(KUBE_TEMP, 'install.sh'))
        end
      end
    end

    def exec hosts: nil
      unless hosts
        hosts = []
        self.kubelets.each do |_, v|
          hosts << v
        end
      end

      uploader = Porkadot::Install::Uploader.new(global_config)
      on(hosts) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        execute(:rm, '-rf', KUBE_TEMP, *LEGACY_TEMPS)
        # Node specific assets are overlaid on the defaults.
        uploader.upload_tree(self, host.global_config.kubelet_default.target_path, KUBE_TEMP)
        uploader.upload_tree(self, host.config.target_path, KUBE_TEMP)
      end

      return hosts
    end

    def backup_etcd host: nil, path: "./backup/etcd.db"
      host = self.etcd_hosts(host).first

      on(:local) do |local|
        execute(:mkdir, '-p', File.dirname(path))
      end

      options = self.etcd_options
      snapshot = "#{KUBE_TEMP}/etcd.db"
      on(host) do |host|
        execute(:mkdir, '-p', KUBE_TEMP)
        uid = capture(:id, '-u')
        gid = capture(:id, '-g')
        # The etcd client key is readable only by root.
        as user: 'root' do
          execute(:"/opt/bin/etcdctl", *options, "snapshot", "save", snapshot)
          execute(:chown, "#{uid}:#{gid}", snapshot)
          execute(:chmod, '0600', snapshot)
        end
        download! snapshot, path
        execute(:rm, '-f', snapshot)
      end

      # The snapshot contains Secrets.
      File.chmod(0600, path)
    end

    # How far a restore moves the revision. The bump has to cover what was
    # written since the snapshot, which RESTORE_BUMP_REVISION alone does
    # only for the first restore: after it the revision is already about as
    # high, and an older snapshot would come back below what clients saw.
    # Clients watching from a revision etcd has not reached yet get no
    # error and no events. So the bump covers the current revision too and
    # keeps RESTORE_BUMP_REVISION as the margin above it.
    def self.restore_bump_revision current:, snapshot:
      [RESTORE_BUMP_REVISION, current - snapshot + RESTORE_BUMP_REVISION].max
    end

    # The highest revision any etcd member answers with, or nil when none
    # answers. Read before etcd is stopped for a restore. A member lagging
    # behind is within the margin of restore_bump_revision.
    def current_etcd_revision
      options = self.etcd_options
      revisions = {}
      lock = Mutex.new
      on(self.etcd_hosts) do |host|
        # The etcd client key is readable only by root.
        as user: 'root' do
          out = capture(:"/opt/bin/etcdctl", *options, 'endpoint', 'status', '-w', 'json',
            raise_on_non_zero_exit: false)
          revision = begin
            JSON.parse(out).first&.dig('Status', 'header', 'revision')
          rescue JSON::ParserError
            nil
          end
          lock.synchronize { revisions[host.config.name] = revision }
        end
      end
      logger.info "etcd revisions: " + revisions.sort.map { |k, v| "#{k}=#{v || 'unreadable'}" }.join(', ')
      return revisions.values.compact.max
    end

    # current_revision is the one read before etcd was stopped. bump_revision
    # is used as it is instead, when given.
    def restore_etcd path: "./backup/etcd.db", current_revision: nil, bump_revision: nil
      require 'date'
      hosts = self.etcd_hosts
      list = self

      etcd_nodes = self.global_config.etcd_nodes
      snapshot = "#{KUBE_TEMP}/etcd.db"
      bumps = self.global_config.etcd.restore_bumps_revision?
      if bumps
        unless current_revision || bump_revision
          raise Porkadot::Error, "The current etcd revision is not known. " \
            "Give the amount to move the revision by with --bump-revision."
        end
      elsif bump_revision
        raise Porkadot::Error, "etcd.image_tag #{self.global_config.etcd.image_tag} is older than 3.5.10, " \
          "whose etcdutl has no --bump-revision."
      end

      on(hosts) do |host|
        execute(:rm, '-rf', KUBE_TEMP, *LEGACY_TEMPS)
        execute(:mkdir, '-p', KUBE_TEMP)
        upload! path, snapshot
      end

      bump = []
      if bumps
        unless bump_revision
          snapshot_revision = self.snapshot_revision(hosts.first, snapshot)
          bump_revision = self.class.restore_bump_revision(current: current_revision, snapshot: snapshot_revision)
          logger.info "Restore with --bump-revision #{bump_revision}: current revision #{current_revision}, " \
            "snapshot revision #{snapshot_revision}, restored revision #{snapshot_revision + bump_revision}"
        else
          logger.info "Restore with --bump-revision #{bump_revision} as given"
        end
        bump = ["--bump-revision", bump_revision.to_s, "--mark-compacted"]
      end

      on(hosts) do |host|
        etcd_node = etcd_nodes[host.config.name]
        as user: 'root' do
          execute(:mkdir, '-p', ETCD_TEMP)
          if test("[ -d #{ETCD_DATA_DIR} ]")
            execute(:mv, ETCD_DATA_DIR, "#{ETCD_TEMP}/data-#{DateTime.now.to_s}")
          end
          # etcdctl 3.6 has no snapshot restore.
          execute(:"/opt/bin/etcdutl", "snapshot", "restore", snapshot,
            "--data-dir", ETCD_DATA_DIR,
            "--name", etcd_node.member_name,
            "--initial-cluster", etcd_node.initial_cluster.map{|k,v| "#{k}=#{v}"}.join(','),
            "--initial-advertise-peer-urls", etcd_node.advertise_peer_urls.join(','),
            *bump)
        end
      end
    end

    def snapshot_revision host, snapshot
      out = nil
      on(host) do
        as user: 'root' do
          out = capture(:"/opt/bin/etcdutl", 'snapshot', 'status', snapshot, '-w', 'json',
            raise_on_non_zero_exit: false)
        end
      end
      revision = begin
        JSON.parse(out)['revision']
      rescue JSON::ParserError, TypeError
        nil
      end
      return revision if revision.is_a?(Integer)
      raise Porkadot::Error, "Could not read the revision of #{snapshot} with etcdutl snapshot status " \
        "on #{host.hostname}: #{out.inspect}\n" \
        "etcd is stopped and its data is untouched. porkadot etcd start brings it back."
    end

    # Waits until every etcd member answers endpoint health.
    def wait_etcd_health hosts: nil, timeout: DEFAULT_RESTORE_TIMEOUT
      list = self
      options = self.etcd_options
      deadline = now + timeout
      on(self.etcd_hosts(hosts), in: :sequence, wait: 0) do |host|
        # The etcd client key is readable only by root.
        as user: 'root' do
          list.wait_until(self, deadline, "etcd health on #{host.hostname}", <<~HINT) do
            Check the etcd Pod on #{host.hostname} (crictl ps --name etcd, crictl logs).
          HINT
            test(:"/opt/bin/etcdctl", *options, 'endpoint', 'health') ? nil : 'not healthy'
          end
        end
      end
    rescue SSHKit::Runner::ExecuteError => e
      raise e.cause if e.cause.is_a?(Porkadot::Error)
      raise
    end

    # Replaces the kube-apiserver, kube-controller-manager and kube-scheduler
    # on every master after a restore, so that none of them keeps serving or
    # acting on what it cached before. Their containers are stopped through
    # crictl and the kubelet starts them again, which needs no API.
    # kube-apiservers go first, and the rest follows once every one of them
    # is ready again.
    def restart_control_plane timeout: DEFAULT_RESTORE_TIMEOUT
      list = self
      deadline = now + timeout
      port = global_config.k8s.apiserver.bind_port
      hosts = self.master_hosts
      CONTROL_PLANE_CONTAINERS.each do |name|
        # Every master runs a kube-apiserver. The controller-manager and the
        # scheduler run on some masters only.
        optional = name != 'kube-apiserver'
        on(hosts, in: :sequence, wait: 0) do |host|
          as user: 'root' do
            with(container_runtime_endpoint: CONTAINERD_ENDPOINT) do
              old = list.containers(self, name)
              next if old.empty? && optional
              old.each { |id| execute(:"/opt/bin/crictl", 'stop', id) }
              list.wait_until(self, deadline, "#{name} on #{host.hostname}", <<~HINT) do
                The kubelet did not start #{name} again. Check it with
                  crictl ps -a --name #{name}
                on #{host.hostname}, and the kubelet's log.
              HINT
                current = list.containers(self, name)
                (current.empty? || !(current & old).empty?) ? 'not restarted' : nil
              end
              if name == 'kube-apiserver'
                endpoint = "https://127.0.0.1:#{port}/readyz"
                list.wait_until(self, deadline, "#{name} on #{host.hostname} to be ready", <<~HINT) do
                  #{endpoint} did not answer. Check crictl logs of #{name} on #{host.hostname}.
                HINT
                  test(:curl, '-skf', endpoint) ? nil : endpoint
                end
              end
            end
          end
        end
      end
    rescue SSHKit::Runner::ExecuteError => e
      raise e.cause if e.cause.is_a?(Porkadot::Error)
      raise
    end

    # IDs of the running containers named exactly name.
    def containers backend, name
      backend.capture(:"/opt/bin/crictl", 'ps', '-q', '--name', "^#{name}$").split
    end

    def wait_until backend, deadline, subject, hint
      backend.info "Start to wait for #{subject}"
      loop do
        pending = yield
        return if pending.nil?
        if now >= deadline
          raise Porkadot::Error, "Timed out waiting for #{subject}: #{pending}\n#{hint}"
        end
        backend.info "Still waiting for #{subject}: #{pending}"
        pause
      end
    end

    def master_hosts
      self.kubelets.values.select { |k| k.config.apiserver? }
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def pause
      sleep POLL_INTERVAL
    end

    def start_etcd hosts: nil
      hosts = self.etcd_hosts(hosts)

      on(hosts) do |host|
        as user: 'root' do
          execute(:mkdir, '-p', ETCD_TEMP)

          with(container_runtime_endpoint: "unix:///run/containerd/containerd.sock") do
            result = capture(:"/opt/bin/crictl", 'ps', '-q', '--name', 'etcd')
            if result.empty?
              info 'Trying to start etcd'
              execute(:mv, "#{ETCD_TEMP}/etcd-server.yaml", "/etc/kubernetes/manifests/etcd-server.yaml")
            else
              info 'etcd is already started...'
            end
          end
        end
      end
    end

    def stop_etcd hosts: nil
      hosts = self.etcd_hosts(hosts)

      on(hosts) do |host|
        as user: 'root' do
          execute(:mkdir, '-p', ETCD_TEMP)

          info "Waiting for etcd to stop..."
          with(container_runtime_endpoint: "unix:///run/containerd/containerd.sock") do
            unless capture(:"/opt/bin/crictl", 'ps', '-q', '--name', 'etcd').empty?
              execute(:mv, "/etc/kubernetes/manifests/etcd-server.yaml", "#{ETCD_TEMP}/etcd-server.yaml")
              while capture(:"/opt/bin/crictl", 'ps', '-q', '--name', 'etcd') != ''
                info 'Still waiting for stopping etcd...'
                sleep 5
              end
            end
          end
          info 'etcd was stopped.'
        end
      end
    end

    # Returns etcd member hosts. When node is given, it is looked up by its
    # name in porkadot.yaml so that the node's connection settings are used.
    def etcd_hosts node=nil
      if node
        host = self[node]
        raise Porkadot::Error, "Unknown node: #{node}" unless host
        raise Porkadot::Error, "Node is not an etcd member: #{node}" unless host.etcd?
        return [host]
      end

      self.kubelets.values.select(&:etcd?)
    end

    def etcd_options
      %w(
        --cacert /etc/etcd/pki/ca.crt
        --cert /etc/etcd/pki/etcd.crt
        --key /etc/etcd/pki/etcd.key
        --endpoints=https://127.0.0.1:2379
      )
    end

    def [](name)
      self.kubelets[name]
    end
  end

  class Kubelet < SSHKit::Host
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger
    attr_reader :connection

    def initialize config
      @config = config
      @logger = config.logger
      @global_config = config.config
      @connection = config.connection.to_hash(symbolize_keys: true)
      super(@connection)
    end

    def etcd?
      return self.config.raw.labels && self.config.raw.labels[Porkadot::ETCD_MEMBER_LABEL]
    end
  end
end; end
