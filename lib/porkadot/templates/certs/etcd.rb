
class Porkadot::Templates::Certs::Etcd < Porkadot::Templates::Certs

  def initialize config
    asset = Porkadot::Assets::Certs::Etcd.new(config)
    super config, asset
  end

  def ca_name
    '/CN=kube-ca'
  end

  def client_name
    '/CN=etcd-client'
  end
end
