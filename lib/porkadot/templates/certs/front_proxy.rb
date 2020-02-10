
class Porkadot::Templates::Certs::FrontProxy < Porkadot::Templates::Certs

  def initialize config
    asset = Porkadot::Assets::Certs::FrontProxy.new(config)
    super config, asset
  end

  def ca_name
    '/CN=front-proxy-ca'
  end

  def client_name
    '/CN=aggregator-client'
  end
end
