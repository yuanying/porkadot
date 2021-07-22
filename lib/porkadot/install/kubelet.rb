module Porkadot; module Install
  class KubeletList
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'kubelet')
    KUBE_SECRETS_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.kubelet')
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

  end
end; end
