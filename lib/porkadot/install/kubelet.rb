module Porkadot; module Install
  class KubeletList
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'kubelet')
    KUBE_SECRETS_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.kubelet')
    KUBE_DEFAULT_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.default')
    ETCD_TEMP = '/opt/porkadot'
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
      unless hosts
        hosts = []
        self.kubelets.each do |_, v|
          hosts << v
        end
      end

      on(hosts) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
          execute(:rm, '-rf', KUBE_SECRETS_TEMP)
        end
        upload! host.config.target_path, KUBE_TEMP, recursive: true
        upload! host.config.target_secrets_path, KUBE_SECRETS_TEMP, recursive: true
        execute(:cp, '-r', KUBE_SECRETS_TEMP + '/*', KUBE_TEMP)

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'setup-containerd.sh'))
        end
      end
    end

    def setup_default hosts: nil, force: false
      unless hosts
        hosts = []
        self.kubelets.each do |_, v|
          hosts << v
        end
      end

      on(hosts) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
          execute(:rm, '-rf', KUBE_SECRETS_TEMP)
        end
        upload! host.global_config.kubelet_default.target_path, KUBE_TEMP, recursive: true
        upload! host.global_config.kubelet_default.target_secrets_path, KUBE_SECRETS_TEMP, recursive: true
        execute(:cp, '-r', KUBE_SECRETS_TEMP + '/*', KUBE_TEMP)

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'install.sh'))
        end
      end
    end

    def install hosts: nil, force: false
      unless hosts
        hosts = []
        self.kubelets.each do |_, v|
          hosts << v
        end
      end

      on(hosts) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
          execute(:rm, '-rf', KUBE_SECRETS_TEMP)
        end
        upload! host.config.target_path, KUBE_TEMP, recursive: true
        upload! host.config.target_secrets_path, KUBE_SECRETS_TEMP, recursive: true
        execute(:cp, '-r', KUBE_SECRETS_TEMP + '/*', KUBE_TEMP)

        as user: 'root' do
          unless test("[ -f /opt/bin/kubelet-#{host.global_config.k8s.kubernetes_version} ]") && !force
            execute(:bash, File.join(KUBE_TEMP, 'install-deps.sh'))
          end
          execute(:bash, File.join(KUBE_TEMP, 'install-pkgs.sh'))
          execute(:bash, File.join(KUBE_TEMP, 'install.sh'))
        end
      end
    end

    def backup_etcd host: nil, path: "./backup/etcd.db"
      unless host
        self.kubelets.each do |_, v|
          if v.etcd?
            host = v
          end
        end
      end

      on(:local) do |local|
        execute(:mkdir, '-p', File.dirname(path))
      end

      options = self.etcd_options
      on(host) do |host|
        execute(:mkdir, '-p', KUBE_TEMP)
        execute(:"/opt/bin/etcdctl", *options, "snapshot", "save", "#{KUBE_TEMP}/etcd.db")
        download! "#{KUBE_TEMP}/etcd.db", path
      end
    end

    def restore_etcd path: "./backup/etcd.db"
      require 'date'
      hosts = []
      self.kubelets.each do |_, v|
        hosts << v if v.etcd?
      end

      options = self.etcd_options
      on(hosts) do |host|
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
          execute(:rm, '-rf', KUBE_SECRETS_TEMP)
        end
        execute(:mkdir, '-p', KUBE_TEMP)
        upload! path, "#{KUBE_TEMP}/etcd.db"

        as user: 'root' do
          execute(:mkdir, '-p', ETCD_TEMP)
          if test('[ -d /var/lib/etcd ]')
            execute(:mv, '/var/lib/etcd', "${ETCD_TEMP}/data-#{DateTime.now.to_s}")
          end
          execute(:"/opt/bin/etcdctl", *options, "snapshot", "restore", "#{KUBE_TEMP}/etcd.db")
        end
      end
    end

    def start_etcd hosts: nil
      unless hosts
        hosts = []
        self.kubelets.each do |_, v|
          hosts << v if v.etcd?
        end
      end

      on(hosts) do |host|
        as user: 'root' do
          execute(:mkdir, '-p', ETCD_TEMP)

          result = capture(:"/opt/bin/crictl", 'ps', '-q', '--name', 'etcd')
          with(container_runtime_endpoint: "unix:///run/containerd/containerd.sock") do
            if result.empty?
              info 'Trying to start etcd'
              execute(:mv, "${ETCD_TEMP}/etcd-server.yaml", "/etc/kubernetes/manifests/etcd-server.yaml")
            else
              info 'etcd is already started...'
            end
          end
        end
      end
    end

    def stop_etcd hosts: nil
      unless hosts
        hosts = []
        self.kubelets.each do |_, v|
          hosts << v if v.etcd?
        end
      end

      on(hosts) do |host|
        as user: 'root' do
          execute(:mkdir, '-p', ETCD_TEMP)

          info "Waiting for etcd to stop..."
          with(container_runtime_endpoint: "unix:///run/containerd/containerd.sock") do
            unless capture(:"/opt/bin/crictl", 'ps', '-q', '--name', 'etcd').empty?
              execute(:mv, "/etc/kubernetes/manifests/etcd-server.yaml", "${ETCD_TEMP}/etcd-server.yaml")
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
