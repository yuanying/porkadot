
module Porkadot; module Configs
  class Kubernetes
    include Porkadot::ConfigUtils
    attr_reader :networking
    attr_reader :proxy

    def initialize config
      @config = config
      @raw = config.raw.kubernetes

      @networking = Networking.new(config)
      @proxy = Proxy.new(config)
    end

    def target_path
      File.join(self.config.assets_dir, 'kubernetes')
    end

    def manifests_path
      File.join(self.target_path, 'manifests')
    end

    class Proxy
      include Porkadot::ConfigUtils

      def initialize config
        @config = config
        @raw = config.raw.kubernetes.proxy
      end

      def proxy_config kubeconfig=nil
        self.raw.config['clusterCIDR'] = config.k8s.networking.service_subnet
        if kubeconfig
          self.raw.config['clientConnection']['kubeconfig'] = kubeconfig
        end
        self.raw.config.to_hash.to_yaml
      end
    end

    class Networking
      include Porkadot::ConfigUtils

      def initialize config
        @config = config
        @raw = config.raw.kubernetes.networking
      end

      def dns_ip
        cluster_ip_range = IPAddr.new(self.service_subnet)
        cluster_ip_range.to_range.first(11)[10].to_s
      end
    end
  end
end; end
