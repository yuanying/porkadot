
class Porkadot::Assets::Certs::Kubernetes < Porkadot::Assets::Certs

  def initialize global_config
    config = Porkadot::Configs::Certs::Kubernetes.new(global_config)
    super config
  end

  def ca_name
    '/CN=kube-ca'
  end

  def client_name
    '/O=system:masters/CN=admin'
  end

  def apiserver_key
    @apiserver_key ||= private_key(config.apiserver_key_path)
    return @apiserver_key
  end

  def apiserver_cert(refresh=false)
    return @apiserver_cert if defined?(@apiserver_cert)
    if File.file?(config.apiserver_cert_path) and !refresh
      self.logger.debug("--> APIserver cert already exists, skipping: #{config.apiserver_cert_path}")
      @apiserver_cert = OpenSSL::X509::Certificate.new(File.read(config.apiserver_cert_path))
    else
      @apiserver_cert = _apiserver_cert(config.apiserver_cert_path, self.apiserver_key, self.ca_cert, self.ca_key)
    end
    return @apiserver_cert
  end

  def kubelet_client_key
    @kubelet_client_key ||= private_key(config.kubelet_client_key_path)
    return @kubelet_client_key
  end

  def kubelet_client_cert(refresh=false)
    return @kubelet_client_cert if defined?(@kubelet_client_cert)
    if File.file?(config.kubelet_client_cert_path) and !refresh
      self.logger.debug("--> Kubelet client cert already exists, skipping: #{config.kubelet_client_cert_path}")
      @kubelet_client_cert = OpenSSL::X509::Certificate.new(File.read(config.kubelet_client_cert_path))
    else
      @kubelet_client_cert = _client_cert(
        config.kubelet_client_cert_path,
        '/O=system:masters/CN=kube-kubelet-client',
        self.kubelet_client_key,
        self.ca_cert(false),
        self.ca_key
      )
    end
    return @kubelet_client_cert
  end

  def sa_private_key
    @sa_private_key ||= private_key(config.sa_private_key_path)
    return @sa_private_key
  end

  def sa_public_key
    @sa_public_key ||= public_key(config.sa_public_key_path, self.sa_private_key)
    return @sa_public_key
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
    if self.global_config.k8s.control_plane_endpoint
      host = self.global_config.k8s.control_plane_endpoint.split(':')[0]
      self.ipaddr?(host) ? ips << host : dns_names << host
    end
    self.global_config.nodes.each do |node|
      k = node.name
      v = node
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
      DNS:kubernetes.default.svc.#{self.global_config.k8s.networking.dns_domain}
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
