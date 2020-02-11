
module Porkadot; module Configs; module Certs
  class Kubernetes
    include Porkadot::Configs::Certs
    attr_reader :config
    attr_reader :logger

    def initialize config
      @config = config
      @logger = config.logger
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
