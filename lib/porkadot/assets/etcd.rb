require 'openssl'
require 'fileutils'
require 'erb'
require 'base64'

module Porkadot; module Assets
  class EtcdList
    attr_reader :global_config
    attr_reader :logger
    attr_reader :nodes

    def initialize global_config
      @global_config = global_config
      @logger = global_config.logger
      @nodes = {}
      global_config.etcd_nodes.each do |k, config|
        @nodes[k] = EtcdNode.new(config)
      end
    end

    def render
      self.nodes.each do |_, v|
        v.render
      end
    end

    def [](name)
      self.nodes[name]
    end
  end

  class EtcdNode
    ETCD_TEMPLATE_DIR = File.join(File.dirname(__FILE__), "etcd")

    attr_reader :global_config
    attr_reader :config
    attr_reader :logger
    attr_reader :certs

    def initialize config
      @config = config
      @logger = config.logger
      @global_config = config.config
      @certs = Porkadot::Assets::Certs::Etcd.new(global_config)
    end

    def render
      logger.info "--> Rendering #{config.name} node"
      unless File.directory?(config.etcd_path)
        FileUtils.mkdir_p(config.etcd_path)
      end
      render_ca_crt
      render_etcd_crt
      render_etcd_server_yaml
      render_install_sh
    end

    def render_ca_crt
      logger.info "----> ca.crt"
      open(config.ca_crt_path, 'w') do |out|
        out.write self.certs.ca_cert(false).to_pem
      end
    end

    def render_etcd_crt
      logger.info "----> etcd.crt"
      self.etcd_key
      self.etcd_cert(true)
    end

    def render_etcd_server_yaml
      logger.info "----> etcd-server.yaml"
      open(File.join(ETCD_TEMPLATE_DIR, 'etcd-server.yaml.erb')) do |io|
        open(config.etcd_server_yaml_path, 'w') do |out|
          out.write ERB.new(io.read, trim_mode: '-').result_with_hash(
            config: config,
            global_config: global_config,
            etcd: global_config.etcd,
          )
        end
      end
    end

    def render_install_sh
      logger.info "----> install.sh"
      open(File.join(ETCD_TEMPLATE_DIR, 'install.sh.erb')) do |io|
        open(config.install_sh_path, 'w') do |out|
          out.write ERB.new(io.read, trim_mode: '-').result_with_hash(
            config: config,
            global_config: global_config,
            etcd: global_config.etcd,
          )
        end
      end
    end

    def etcd_key
      @etcd_key ||= certs.private_key(config.etcd_key_path)
      return @etcd_key
    end

    def etcd_cert(refresh=false)
      return @etcd_cert if defined?(@etcd_cert)
      if File.file?(config.etcd_crt_path) and !refresh
        self.logger.debug("--> Etcd cert already exists, skipping: #{config.etcd_cert_path}")
        @etcd_cert = OpenSSL::X509::Certificate.new(File.read(config.etcd_cert_path))
      else
        ca_key = self.certs.ca_key
        ca_cert = self.certs.ca_cert(false)
        @etcd_cert = certs.unsigned_cert(
          "/O=porkadot:etcd-servers/CN=porkadot:etcd-server-#{config.member_name}",
          self.etcd_key, ca_cert,
          1 * 365 * 24 * 60 * 60
        )

        ef = OpenSSL::X509::ExtensionFactory.new
        ef.subject_certificate = @etcd_cert
        ef.issuer_certificate = ca_cert
        @etcd_cert.add_extension(ef.create_extension("basicConstraints","CA:FALSE",true))
        @etcd_cert.add_extension(ef.create_extension("keyUsage","nonRepudiation, digitalSignature, keyEncipherment", true))
        @etcd_cert.add_extension(ef.create_extension("extendedKeyUsage","clientAuth, serverAuth",true))

        @etcd_cert.add_extension(ef.create_extension("subjectAltName", self.config.additional_sans.join(','), true))
        @etcd_cert.sign(ca_key, OpenSSL::Digest::SHA256.new)

        File.open config.etcd_crt_path, 'wb' do |f|
          f.write @etcd_cert.to_pem
        end
      end
      return @etcd_cert
    end

  end
end; end
