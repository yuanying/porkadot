module Porkadot; module Configs
  class Kubelet
    include Porkadot::ConfigUtils
    attr_reader :config
    attr_reader :logger
    attr_reader :name
    attr_reader :raw

    def initialize config, name, raw
      @config = config
      @logger = config.logger
      @name = name
      @raw = raw
    end

    def kubelet_path
      File.join(self.config.assets_dir, 'kubelet', name)
    end

    def config_path
      File.join(self.kubelet_path, 'config.yaml')
    end

    def kubelet_service_path
      File.join(self.kubelet_path, 'kubelet.service')
    end

    def ca_crt_path
      File.join(self.kubelet_path, 'ca.crt')
    end

    def install_sh_path
      File.join(self.kubelet_path, 'install.sh')
    end

    def bootstrap_kubeconfig_path
      File.join(self.kubelet_path, 'bootstrap-kubelet.conf')
    end

    def bootstrap_key_path
      File.join(self.kubelet_path, 'bootstrap.key')
    end

    def bootstrap_cert_path
      File.join(self.kubelet_path, 'bootstrap.crt')
    end
  end
end; end

