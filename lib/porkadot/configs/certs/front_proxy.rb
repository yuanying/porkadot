
module Porkadot; module Configs; class Certs
  class FrontProxy
    include Porkadot::Configs::CertsUtils
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
      File.join(self.certs_dir, 'front-proxy-ca.key')
    end

    def ca_cert_path
      File.join(self.certs_dir, 'front-proxy-ca.crt')
    end

    def client_key_path
      File.join(self.certs_dir, 'front-proxy-client.key')
    end

    def client_cert_path
      File.join(self.certs_dir, 'front-proxy-client.crt')
    end
  end
end; end; end
