
module Porkadot; module Configs
  class Bootstrap
    class Kubelet < Porkadot::Configs::Kubelet
      attr_reader :bootstrap_config
      def initialize bootstrap_config
        @bootstrap_config = bootstrap_config
        super bootstrap_config.config, 'bootstrap', bootstrap_config.raw.node
      end

      def kubelet_path
        File.join(bootstrap_config.bootstrap_path, 'kubelet')
      end
    end

    include Porkadot::ConfigUtils
    attr_reader :config
    attr_reader :logger
    attr_reader :raw
    attr_reader :kubelet_config

    def initialize config
      @config = config
      @logger = config.logger
      @raw = config.raw.bootstrap
      @kubelet_config = Kubelet.new(self)
    end

    def bootstrap_path
      File.join(self.config.assets_dir, 'bootstrap')
    end

    def bootstrap_assets_path
      File.join(self.bootstrap_path, 'bootstrap')
    end

    def secrets_path
      File.join(self.bootstrap_assets_path, 'secrets')
    end

    def kubeconfig_path
      File.join(self.bootstrap_assets_path, 'kubeconfig-bootstrap.yaml')
    end

    def manifests_path
      File.join(self.bootstrap_path, 'manifests')
    end

    def apiserver_path
      File.join(self.manifests_path, 'kube-apiserver.bootstrap.yaml')
    end

    def controller_manager_path
      File.join(self.manifests_path, 'kube-controller-manager.bootstrap.yaml')
    end

    def scheduler_path
      File.join(self.manifests_path, 'kube-scheduler.bootstrap.yaml')
    end

    def install_sh_path
      File.join(self.bootstrap_path, 'install.sh')
    end
  end

end; end
