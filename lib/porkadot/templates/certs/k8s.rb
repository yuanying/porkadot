
class Porkadot::Templates::Certs::Kubernetes < Porkadot::Templates::Certs

  def initialize config
    asset = Porkadot::Assets::Certs::Kubernetes.new(config)
    super config, asset
  end

  def ca_name
    '/CN=kube-ca'
  end

  def client_name
    '/O=system:masters/CN=admin'
  end

  def _apiserver_cert(path, client_key, ca_cert, ca_key)
    cert = unsigned_cert('/CN=apiserver', ca_key, ca_cert, 1 * 365 * 24 * 60 * 60)

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = ca_cert
    cert.add_extension(ef.create_extension("basicConstraints","CA:FALSE",true))
    cert.add_extension(ef.create_extension("keyUsage","nonRepudiation, digitalSignature, keyEncipherment", true))
    cert.add_extension(ef.create_extension("extendedKeyUsage","clientAuth, serverAuth",true))

    cert.add_extension(ef.create_extension("subjectAltName", self.additional_sans.join(','), true))
    cert.sign(ca_key, OpenSSL::Digest::SHA256.new)

    File.open path, 'wb' do |f|
      f.write cert.to_pem
    end

    return cert
  end

  def additional_sans
    dns_names = []
    ips = []
    if self.config.k8s.control_plane_endpoint
      host = self.config.k8s.control_plane_endpoint.split(':')[0]
      self.ipaddr?(host) ? ips << host : dns_names << host
    end
    self.config.nodes.each do |k, v|
      next unless v.labels && v.labels.include?(Porkadot::K8S_MASTER_LABEL)
      self.ipaddr?(k) ? ips << k : dns_names << k
      if v.address
        self.ipaddr?(v.address) ? ips << v.address : dns_names << v.address
      end
    end

    sans = dns_names.map {|v| "DNS:#{v}"} + ips.map {|v| "IP:#{v}"}
    default_sans = %W(
      DNS:kubernetes
      DNS:kubernetes.default
      DNS:kubernetes.default.svc
      DNS:kubernetes.default.svc.#{self.config.k8s.networking.dns_domain}
      IP:127.0.0.1
    )
    return default_sans + sans.uniq
  end

  def ipaddr?(addr)
    IPAddr.new(addr)
    return true
  rescue IPAddr::InvalidAddressError
    return false
  end

end
