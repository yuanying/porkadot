module Porkadot; module Assets
  class Certs
    attr_reader :config
    attr_reader :logger
  
    def initialize config
      @config = config
      @logger = config.logger
    end

    def certs_dir
      File.join(self.config.assets_dir, 'certs')
    end

    def etcd_certs_dir
      File.join(self.certs_dir, 'etcd')
    end

    def etcd_ca_key_path
      File.join(self.etcd_certs_dir, 'ca.key')
    end

    def etcd_ca_cert_path
      File.join(self.etcd_certs_dir, 'ca.crt')
    end

    def etcd_client_key_path
      File.join(self.etcd_certs_dir, 'etcd-client.key')
    end

    def etcd_client_cert_path
      File.join(self.etcd_certs_dir, 'etcd-client.crt')
    end

    def k8s_certs_dir
      File.join(self.certs_dir, 'kubernetes')
    end

    def k8s_ca_key_path
      File.join(self.k8s_certs_dir, 'ca.key')
    end

    def k8s_ca_cert_path
      File.join(self.k8s_certs_dir, 'ca.crt')
    end

    def k8s_apiserver_key_path
      File.join(self.k8s_certs_dir, 'apiserver.key')
    end

    def k8s_apiserver_cert_path
      File.join(self.k8s_certs_dir, 'apiserver.crt')
    end

    def k8s_kubelet_client_key_path
      File.join(self.k8s_certs_dir, 'kubelet-client.key')
    end

    def k8s_kubelet_client_cert_path
      File.join(self.k8s_certs_dir, 'kubelet-client.crt')
    end

    def k8s_admin_key_path
      File.join(self.k8s_certs_dir, 'admin.key')
    end

    def k8s_admin_cert_path
      File.join(self.k8s_certs_dir, 'admin.crt')
    end

    def k8s_front_proxy_ca_key_path
      File.join(self.k8s_certs_dir, 'front-proxy-ca.key')
    end

    def k8s_front_proxy_ca_cert_path
      File.join(self.k8s_certs_dir, 'front-proxy-ca.crt')
    end

    def k8s_front_proxy_key_path
      File.join(self.k8s_certs_dir, 'front-proxy-client.key')
    end

    def k8s_front_proxy_cert_path
      File.join(self.k8s_certs_dir, 'front-proxy-client.crt')
    end

    def k8s_sa_private_key_path
      File.join(self.k8s_certs_dir, 'sa.key')
    end

    def k8s_sa_public_key_path
      File.join(self.k8s_certs_dir, 'sa.pub')
    end

    def k8s_bootstrap_key_path
      File.join(self.k8s_certs_dir, 'bootstrap.key')
    end

    def k8s_bootstrap_cert_path
      File.join(self.k8s_certs_dir, 'bootstrap.crt')
    end
  end
end; end
