require 'openssl'
require 'fileutils'
require 'base64'
#OpenSSL::Random.seed File.read('/dev/random', 16)

module Porkadot; module Assets
end; end

class Porkadot::Assets::Certs
  attr_reader :global_config
  attr_reader :config
  attr_reader :logger

  def initialize config
    @config = config
    @logger = config.logger
    @global_config = config.config
  end

  def to_pem(key_or_cert)
    self.send(key_or_cert.to_sym).to_pem
  end

  def to_base64(key_or_cert)
    Base64.strict_encode64(self.to_pem(key_or_cert))
  end

  def ca_name
    raise "Not implemented"
  end

  def ca_key
    @ca_key ||= private_key(config.ca_key_path)
    return @ca_key
  end

  def ca_cert(refresh=false)
    return @ca_cert if defined?(@ca_cert)
    if File.file?(config.ca_cert_path) and !refresh
      self.logger.debug("--> CA cert already exists, skipping: #{config.ca_cert_path}")
      @ca_cert = OpenSSL::X509::Certificate.new(File.read(config.ca_cert_path))
    else
      @ca_cert = _ca_cert(config.ca_cert_path, self.ca_name, self.ca_key)
    end
    return @ca_cert
  end

  def client_name
    raise "Not implemented"
  end

  def client_key
    @client_key ||= private_key(config.client_key_path)
    return @client_key
  end

  def client_cert(refresh=false)
    return @client_cert if defined?(@client_cert)
    if File.file?(config.client_cert_path) and !refresh
      self.logger.debug("--> Client cert already exists, skipping: #{config.client_cert_path}")
      @client_cert = OpenSSL::X509::Certificate.new(File.read(config.client_cert_path))
    else
      @client_cert = _client_cert(config.client_cert_path, self.client_name, self.client_key, self.ca_cert(false), self.ca_key)
    end
    return @client_cert
  end

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

  def _ca_cert(path, name, root_key)
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

  def _client_cert(path, name, client_key, ca_cert, ca_key)
    cert = unsigned_cert(name, client_key, ca_cert, 1 * 365 * 24 * 60 * 60)

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

end

require 'porkadot/assets/certs/etcd'
require 'porkadot/assets/certs/k8s'
require 'porkadot/assets/certs/front_proxy'
