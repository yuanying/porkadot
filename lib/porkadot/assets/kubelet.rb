module Porkadot; module Assets
  class KubeletList
    attr_reader :config
    attr_reader :kubelets

    def initialize config
      @kubelets = []
      config.nodes.each do |k, node|
        @kubelets << Kubelet.new(config, k, node)
      end
    end
  end

  class Kubelet
    attr_reader :config
    attr_reader :logger
    attr_reader :name
    attr_reader :node

    def initialize config, name, node
      @config = config
      @logger = config.logger
      @name = name
      @node = node
    end

    def kubelet_path
      File.join(self.config.assets_dir, name, 'kubelet')
    end

    def bootstrap_kubeconfig_path
      File.join(self.kubelet_path, 'bootstrap-kubelet.conf')
    end
  end
end; end

