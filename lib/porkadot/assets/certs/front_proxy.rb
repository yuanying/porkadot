
class Porkadot::Assets::Certs::FrontProxy < Porkadot::Assets::Certs

  def initialize global_config
    config = Porkadot::Configs::Certs::FrontProxy.new(global_config)
    super config
  end

  def ca_name
    '/CN=front-proxy-ca'
  end

  def client_name
    '/CN=aggregator-client'
  end
end
