
class Porkadot::Assets::Certs::FrontProxy
  include Porkadot::Assets::CertsUtils
  attr_reader :global_config
  attr_reader :config
  attr_reader :logger

  def initialize global_config
    @config = Porkadot::Configs::Certs::FrontProxy.new(global_config)
    @logger = config.logger
    @global_config = config.config
  end

  def ca_name
    '/CN=front-proxy-ca'
  end

  def client_name
    '/CN=aggregator-client'
  end
end
