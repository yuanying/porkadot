module Porkadot; module Install
  class KubeletList
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'kubelet')
    # Used by porkadot before secrets were merged into the assets tree.
    LEGACY_TEMPS = %w(.kubelet .default .default.kubelet).map { |d| File.join(Porkadot::Install::KUBE_TEMP, d) }
    ETCD_TEMP = '/opt/porkadot'
    ETCD_DATA_DIR = '/var/lib/etcd'
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
          execute(:"/opt/bin/etcdctl", "snapshot", "restore", "#{KUBE_TEMP}/etcd.db",
            "--data-dir", ETCD_DATA_DIR,
            "--name", etcd_node.member_name,
            "--initial-cluster", etcd_node.initial_cluster.map{|k,v| "#{k}=#{v}"}.join(','),
            "--initial-advertise-peer-urls", etcd_node.advertise_peer_urls.join(','))
        end
      end
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
