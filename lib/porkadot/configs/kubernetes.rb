
module Porkadot; module Configs
  class Kubernetes
    include Porkadot::ConfigUtils
    attr_reader :networking
    attr_reader :proxy
    attr_reader :apiserver
    attr_reader :controller_manager
    attr_reader :scheduler

    def initialize config
      @config = config
      @raw = config.raw.kubernetes

      @networking = Networking.new(config)
      @proxy = Proxy.new(config)
      @apiserver = Apiserver.new(config)
      @controller_manager = ControllerManager.new(config)
      @scheduler = Scheduler.new(config)
    end

    def target_path
      File.join(self.config.assets_dir, 'kubernetes')
    end

    def manifests_path
      File.join(self.target_path, 'manifests')
    end

    module Component
      RECOMMENDED_LABEL_PREFIX = 'app.kubernetes.io'
      def labels
        {
          "#{RECOMMENDED_LABEL_PREFIX}/name": self.component_name,
          "#{RECOMMENDED_LABEL_PREFIX}/component": self.component_name,
          "#{RECOMMENDED_LABEL_PREFIX}/instance": "#{self.component_name}-porkadot",
          "#{RECOMMENDED_LABEL_PREFIX}/version": self.config.k8s.kubernetes_version,
          "#{RECOMMENDED_LABEL_PREFIX}/part-of": 'kubernetes',
          "#{RECOMMENDED_LABEL_PREFIX}/managed-by": 'porkadot',
        }
      end
    end

    class Apiserver
      include Porkadot::ConfigUtils
      include Component

      def initialize config
        @config = config
        @raw = config.raw.kubernetes.apiserver
      end

      def component_name
        'kube-apiserver'
      end
    end

    class Scheduler
      include Porkadot::ConfigUtils
      include Component

      def initialize config
        @config = config
        @raw = config.raw.kubernetes.scheduler
      end

      def component_name
        'kube-scheduler'
      end
    end

    class ControllerManager
      include Porkadot::ConfigUtils
      include Component

      def initialize config
        @config = config
        @raw = config.raw.kubernetes.controller_manager
      end

      def component_name
        'kube-controller-manager'
      end
    end

    class Proxy
      include Porkadot::ConfigUtils
      include Component

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

      def component_name
        'kube-proxy'
      end
    end

    class Networking
      include Porkadot::ConfigUtils

      def initialize config
        @config = config
        @raw = config.raw.kubernetes.networking
      end

      def kubernetes_ip
        cluster_ip_range = IPAddr.new(self.service_subnet)
        cluster_ip_range.to_range.first(2)[1].to_s
      end

      def dns_ip
        cluster_ip_range = IPAddr.new(self.service_subnet)
        cluster_ip_range.to_range.first(11)[10].to_s
      end
    end
  end
end; end
