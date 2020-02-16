
module Porkadot; module Configs; class Certs
  class Etcd
    include Porkadot::Configs::CertsUtils
    attr_reader :config
    attr_reader :logger

    def initialize config
      @config = config
      @logger = config.logger
    end

    def certs_dir
      File.join(self.certs_root_dir, 'etcd')
    end

    def ca_key_path
      File.join(self.certs_dir, 'ca.key')
    end

    def ca_cert_path
      File.join(self.certs_dir, 'ca.crt')
    end

    def client_key_path
      File.join(self.certs_dir, 'etcd-client.key')
    end

    def client_cert_path
      File.join(self.certs_dir, 'etcd-client.crt')
    end
  end
end; end; end
