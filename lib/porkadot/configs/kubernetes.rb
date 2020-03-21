
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

    def control_plane_endpoint_host_and_port
      endpoint = self.config.k8s.control_plane_endpoint
      raise "kubernetes.control_plane_endpoint should not be nil" unless endpoint
      index = endpoint.rindex(':')
      return [endpoint[0, index], endpoint[index+1, 6]]
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

      def log_level
        config.kubernetes.log_level || raw.log_level || 2
      end

      def component_name
        'kube-apiserver'
      end

      def args
        return self.default_args.merge(self.extra_args.map{|i| i.split('=', 2)}.to_h || {})
      end

      def default_args
        return %W(
          --advertise-address=$(POD_IP)
          --allow-privileged=true
          --authorization-mode=Node,RBAC
          --bind-address=0.0.0.0
          --client-ca-file=/etc/kubernetes/pki/ca.crt
          --enable-bootstrap-token-auth=true
          --etcd-cafile=/etc/kubernetes/pki/etcd-client-ca.crt
          --etcd-certfile=/etc/kubernetes/pki/etcd-client.crt
          --etcd-keyfile=/etc/kubernetes/pki/etcd-client.key
          --etcd-servers=#{config.etcd.advertise_client_urls.join(',')}
          --kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt
          --kubelet-client-certificate=/etc/kubernetes/pki/kubelet-client.crt
          --kubelet-client-key=/etc/kubernetes/pki/kubelet-client.key
          --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
          --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt
          --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key
          --requestheader-allowed-names=aggregator-client
          --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt
          --requestheader-extra-headers-prefix=X-Remote-Extra-
          --requestheader-group-headers=X-Remote-Group
          --requestheader-username-headers=X-Remote-User
          --secure-port=#{self.bind_port}
          --service-account-key-file=/etc/kubernetes/pki/sa.pub
          --service-cluster-ip-range=#{config.k8s.networking.service_subnet}
          --storage-backend=etcd3
          --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
          --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
          --v=#{self.log_level}
        ).map {|i| i.split('=', 2)}.to_h
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
