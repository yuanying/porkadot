
module Porkadot; module Configs
  class Bootstrap
    include Porkadot::ConfigUtils
    attr_reader :config
    attr_reader :logger
    attr_reader :raw

    def initialize config
      @config = config
      @logger = config.logger
      @raw = config.raw.bootstrap
    end

    def node
      self.raw.node ? self.config.nodes[self.raw.node] : self.config.nodes[self.config.nodes.keys[0]]
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

  end

end; end
