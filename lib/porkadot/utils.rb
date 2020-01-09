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

  def ca_cert(path, name, root_key)
    root_ca = OpenSSL::X509::Certificate.new

    root_ca.version = 2 # cf. RFC 5280 - to make it a "v3" certificate
    root_ca.serial = 1
    root_ca.subject = OpenSSL::X509::Name.parse "/CN=#{name}"
    root_ca.issuer = root_ca.subject # root CA's are "self-signed"
    root_ca.public_key = root_key.public_key
    root_ca.not_before = Time.now
    root_ca.not_after = root_ca.not_before + 2 * 365 * 24 * 60 * 60 # 2 years validity
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
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.parse "/CN=#{name}"
    cert.issuer = ca_cert.subject # root CA is the issuer
    cert.public_key = client_key.public_key
    cert.not_before = Time.now
    cert.not_after = cert.not_before + 1 * 365 * 24 * 60 * 60 # 1 years validity
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
