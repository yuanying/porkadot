require 'openssl'
require 'fileutils'
require 'erb'
require 'base64'

module Porkadot; module Assets
  class KubeletList
    attr_reader :global_config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @logger = global_config.logger
    end

    def render
      global_config.nodes.each do |config|
        Kubelet.new(config).render
      end
    end
  end

  class Kubelet
    KUBELETE_TEMPLATE_DIR = File.join(File.dirname(__FILE__), "kubelet")

    attr_reader :global_config
    attr_reader :config
    attr_reader :logger
    attr_reader :certs

    def initialize config
      @config = config
      @logger = config.logger
      @global_config = config.config
      @certs = Porkadot::Assets::Certs::Kubernetes.new(global_config)
    end

    def render
      logger.info "--> Rendering #{config.name} node"
      unless File.directory?(config.kubelet_path)
        FileUtils.mkdir_p(config.kubelet_path)
      end
      render_bootstrap_kubeconfig
      render_bootstrap_certs
      render_config
      render_kubelet_service
      render_ca_crt
      render_install_sh
      render_install_deps_sh
    end

    def render_bootstrap_kubeconfig
      logger.info "----> bootstrap kubeconfig"
      ca_data = certs.ca_cert.to_pem
      open(File.join(KUBELETE_TEMPLATE_DIR, 'bootstrap-kubelet.conf.erb')) do |io|
        open(config.bootstrap_kubeconfig_path, 'w') do |out|
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            global_config: global_config,
            ca_data: Base64.strict_encode64(ca_data)
          )
        end
      end
    end

    def render_bootstrap_certs
      logger.info "----> bootstrap certs"
      self.bootstrap_key
      self.bootstrap_cert(true)
    end

    def render_config
      logger.info "----> config.yaml"
      open(File.join(KUBELETE_TEMPLATE_DIR, 'config.yaml.erb')) do |io|
        open(config.config_path, 'w') do |out|
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end

    def render_kubelet_service
      logger.info "----> kubelet.service"
      open(File.join(KUBELETE_TEMPLATE_DIR, 'kubelet.service.erb')) do |io|
        open(config.kubelet_service_path, 'w') do |out|
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end

    def render_ca_crt
      logger.info "----> ca.crt"
      open(config.ca_crt_path, 'w') do |out|
        out.write self.certs.ca_cert(false).to_pem
      end
    end

    def render_install_deps_sh
      logger.info "----> install-deps.sh"
      open(File.join(KUBELETE_TEMPLATE_DIR, 'install-deps.sh.erb')) do |io|
        open(config.install_deps_sh_path, 'w') do |out|
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end

    def render_install_sh
      logger.info "----> install.sh"
      open(File.join(KUBELETE_TEMPLATE_DIR, 'install.sh.erb')) do |io|
        open(config.install_sh_path, 'w') do |out|
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end

    def bootstrap_key
      @bootstrap_key ||= certs.private_key(config.bootstrap_key_path)
      return @bootstrap_key
    end

    def bootstrap_cert(refresh=false)
      return @bootstrap_cert if defined?(@bootstrap_cert)
      if File.file?(config.bootstrap_cert_path) and !refresh
        self.logger.debug("--> Bootstrap cert already exists, skipping: #{config.bootstrap_cert_path}")
        @bootstrap_cert = OpenSSL::X509::Certificate.new(File.read(config.bootstrap_cert_path))
      else
        @bootstrap_cert = certs._client_cert(
          config.bootstrap_cert_path,
          "/O=porkadot:node-bootstrappers/CN=node-bootstrapper:#{config.name}",
          self.bootstrap_key,
          self.certs.ca_cert(false),
          self.certs.ca_key
        )
      end
      return @bootstrap_cert
    end

  end
end; end
