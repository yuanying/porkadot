
module Porkadot; module Configs; class Certs
  class Kubernetes
    include Porkadot::Configs::CertsUtils
    attr_reader :config
    attr_reader :logger

    def initialize config
      @config = config
      @logger = config.logger
    end

    def additional_sans
      dns_names = []
      ips = []
      if self.config.k8s.control_plane_endpoint
        host = self.config.k8s.control_plane_endpoint.split(':')[0]
        self.ipaddr?(host) ? ips << host : dns_names << host
      end
      self.config.nodes.each do |_, node|
        k = node.name
        v = node
        next unless v.labels && v.labels.include?(Porkadot::K8S_MASTER_LABEL)
        self.ipaddr?(k) ? ips << k : dns_names << k
        if v.hostname
          self.ipaddr?(v.hostname) ? ips << v.hostname : dns_names << v.hostname
        end
      end

      sans = dns_names.map {|v| "DNS:#{v}"} + ips.map {|v| "IP:#{v}"}
      default_sans = %W(
        DNS:kubernetes
        DNS:kubernetes.default
        DNS:kubernetes.default.svc
        DNS:kubernetes.default.svc.#{self.config.k8s.networking.dns_domain}
        DNS:localhost
        IP:127.0.0.1
      )
      return default_sans + sans.uniq
    end

    def certs_dir
      File.join(self.certs_root_dir, 'kubernetes')
    end

    def ca_key_path
      File.join(self.certs_dir, 'ca.key')
    end

    def ca_cert_path
      File.join(self.certs_dir, 'ca.crt')
    end

    def apiserver_key_path
      File.join(self.certs_dir, 'apiserver.key')
    end

    def apiserver_cert_path
      File.join(self.certs_dir, 'apiserver.crt')
    end

    def kubelet_client_key_path
      File.join(self.certs_dir, 'kubelet-client.key')
    end

    def kubelet_client_cert_path
      File.join(self.certs_dir, 'kubelet-client.crt')
    end

    def admin_key_path
      File.join(self.certs_dir, 'admin.key')
    end
    alias_method :client_key_path, :admin_key_path

    def admin_cert_path
      File.join(self.certs_dir, 'admin.crt')
    end
    alias_method :client_cert_path, :admin_cert_path

    def sa_private_key_path
      File.join(self.certs_dir, 'sa.key')
    end

    def sa_public_key_path
      File.join(self.certs_dir, 'sa.pub')
    end
  end
end; end; end
