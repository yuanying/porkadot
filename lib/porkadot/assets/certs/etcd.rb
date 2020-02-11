
class Porkadot::Assets::Certs::Etcd < Porkadot::Assets::Certs

  def initialize global_config
    config = Porkadot::Configs::Certs::Etcd.new(global_config)
    super config
  end

  def ca_name
    '/CN=kube-ca'
  end

  def client_name
    '/CN=etcd-client'
  end
end
