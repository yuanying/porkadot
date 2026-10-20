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

    def restore_etcd path: "./backup/etcd.db"
      require 'date'
      hosts = self.etcd_hosts

      etcd_nodes = self.global_config.etcd_nodes
      bump = []
      if self.global_config.etcd.restore_bumps_revision?
        bump = ["--bump-revision", RESTORE_BUMP_REVISION.to_s, "--mark-compacted"]
      end
      on(hosts) do |host|
        etcd_node = etcd_nodes[host.config.name]
        execute(:rm, '-rf', KUBE_TEMP, *LEGACY_TEMPS)
        execute(:mkdir, '-p', KUBE_TEMP)
        upload! path, "#{KUBE_TEMP}/etcd.db"

        as user: 'root' do
          execute(:mkdir, '-p', ETCD_TEMP)
          if test("[ -d #{ETCD_DATA_DIR} ]")
            execute(:mv, ETCD_DATA_DIR, "#{ETCD_TEMP}/data-#{DateTime.now.to_s}")
          end
          # etcdctl 3.6 has no snapshot restore.
          execute(:"/opt/bin/etcdutl", "snapshot", "restore", "#{KUBE_TEMP}/etcd.db",
            "--data-dir", ETCD_DATA_DIR,
            "--name", etcd_node.member_name,
            "--initial-cluster", etcd_node.initial_cluster.map{|k,v| "#{k}=#{v}"}.join(','),
            "--initial-advertise-peer-urls", etcd_node.advertise_peer_urls.join(','),
            *bump)
        end
      end
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
