require 'sshkit/dsl'

module Porkadot; module Install
  class KubeletList
    KUBE_TEMP = './kube_temp'
    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :logger
    attr_reader :kubelets

    def initialize global_config
      @global_config = global_config
      @logger = global_config.logger
      @kubelets = {}
      global_config.nodes.each do |config|
        @kubelets[config.name] = Kubelet.new(config)
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
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
        end
        upload! host.config.kubelet_path, KUBE_TEMP, recursive: true

        as user: 'root' do
          unless test("[ -f /opt/bin/kubelet-#{host.global_config.k8s.kubernetes_version} ]") && !force
            execute(:bash, File.join(KUBE_TEMP, 'install-deps.sh'))
          end
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
