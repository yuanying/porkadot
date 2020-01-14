class Porkadot::SubCommandBase < Thor
  def self.banner(command, namespace = nil, subcommand = false)
    "#{basename} #{subcommand_prefix} #{command.usage}"
  end

  def self.subcommand_prefix
    self.name.gsub(%r{.*::}, '').gsub(%r{^[A-Z]}) { |match| match[0].downcase }.gsub(%r{[A-Z]}) { |match| "-#{match[0].downcase}" }
  end
end

module Porkadot::Utils
  def config
    unless defined?(@config)
      opts = options.dup
      opts = opts.merge(parent_options) if parent_options
      @config = Porkadot::Config.new(options[:config])
    end
    @config
  end

  def logger
    self.config.logger
  end
end

require 'openssl'
require 'fileutils'
require 'ipaddr'
OpenSSL::Random.seed File.read('/dev/random', 16)

module Porkadot::Certs
  def private_key(path)
    if File.file?(path)
      self.logger.debug("--> Private key already exists, skipping: #{path}")
      key = OpenSSL::PKey::RSA.new File.read(path)
    else
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir)
      key = OpenSSL::PKey::RSA.new 2048
      File.open path, 'wb' do |f|
        f.write key.export(nil, nil)
      end
    end
    return key
  end

  def public_key(path, key)
    public_key = key.public_key
    if File.file?(path)
      self.logger.debug("--> Public key already exists, skipping: #{path}")
    else
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir)
      File.open path, 'wb' do |f|
        f.write public_key.export(nil, nil)
      end
    end
    return public_key
  end

  def random_number
    return (0...8).map{ (0 + rand(10)) }.join.to_i
  end

  def unsigned_cert(name, key, ca_cert=nil, expire=(1 * 365 * 24 * 60 * 60))
    cert = OpenSSL::X509::Certificate.new

    cert.version = 2 # cf. RFC 5280 - to make it a "v3" certificate
    cert.serial = self.random_number
    cert.subject = OpenSSL::X509::Name.parse name
    if ca_cert
      cert.issuer = ca_cert.subject
    else
      cert.issuer = cert.subject # root CA's are "self-signed"
    end
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = cert.not_before + expire
    return cert
  end

  def ca_cert(path, name, root_key)
    root_ca = unsigned_cert(name, root_key, nil, 2 * 365 * 24 * 60 * 60)

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = root_ca
    ef.issuer_certificate = root_ca
    root_ca.add_extension(ef.create_extension("basicConstraints","CA:TRUE",true))
    root_ca.add_extension(ef.create_extension("keyUsage","keyCertSign, cRLSign", true))
    root_ca.add_extension(ef.create_extension("subjectKeyIdentifier","hash",false))
    root_ca.add_extension(ef.create_extension("authorityKeyIdentifier","keyid:always",false))
    root_ca.sign(root_key, OpenSSL::Digest::SHA256.new)

    File.open path, 'wb' do |f|
      f.write root_ca.to_pem
    end

    return root_ca
  end

  def client_cert(path, name, client_key, ca_cert, ca_key)
    cert = unsigned_cert(name, ca_key, ca_cert, 1 * 365 * 24 * 60 * 60)

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = ca_cert
    cert.add_extension(ef.create_extension("basicConstraints","CA:FALSE",true))
    cert.add_extension(ef.create_extension("keyUsage","nonRepudiation, digitalSignature, keyEncipherment", true))
    cert.add_extension(ef.create_extension("extendedKeyUsage","clientAuth",true))
    cert.sign(ca_key, OpenSSL::Digest::SHA256.new)

    File.open path, 'wb' do |f|
      f.write cert.to_pem
    end

    return cert
  end

  def apiserver_cert(path, client_key, ca_cert, ca_key)
    cert = unsigned_cert('/CN=apiserver', ca_key, ca_cert, 1 * 365 * 24 * 60 * 60)

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = ca_cert
    cert.add_extension(ef.create_extension("basicConstraints","CA:FALSE",true))
    cert.add_extension(ef.create_extension("keyUsage","nonRepudiation, digitalSignature, keyEncipherment", true))
    cert.add_extension(ef.create_extension("extendedKeyUsage","clientAuth, serverAuth",true))

    default_sans = %W(
      DNS:kubernetes
      DNS:kubernetes.default
      DNS:kubernetes.default.svc
      DNS:kubernetes.default.svc.#{self.config.k8s.networking.dns_domain}
      IP:127.0.0.1
    )
    sans = self.additional_sans
    sans = sans + default_sans
    cert.add_extension(ef.create_extension("subjectAltName", sans.join(','), true))
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
    return sans.uniq
  end

  def ipaddr?(addr)
    IPAddr.new(addr)
    return true
  rescue IPAddr::InvalidAddressError
    return false
  end

end
