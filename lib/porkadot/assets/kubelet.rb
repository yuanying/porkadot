require 'openssl'
require 'fileutils'
require 'erb'
require 'base64'

module Porkadot; module Assets
  class KubeletList
    attr_reader :global_config
    attr_reader :logger
    attr_reader :kubelet_default
    attr_reader :kubelets

    def initialize global_config
      @global_config = global_config
      @logger = global_config.logger
      @kubelet_default = KubeletDefault.new(global_config.kubelet_default)
      @kubelets = {}
      global_config.nodes.each do |k, config|
        @kubelets[k] = Kubelet.new(config)
      end
    end

    def render
      self.kubelet_default.render
      self.kubelets.each do |_, v|
        v.render
      end
    end

    def [](name)
      self.kubelets[name]
    end
  end

  class KubeletDefault
    include Porkadot::Assets
    TEMPLATE_DIR = File.join(File.dirname(__FILE__), "kubelet-default")

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
      logger.info "--> Rendering Kubelet default configs"
      unless File.directory?(config.addon_path)
        FileUtils.mkdir_p(config.addon_path)
      end
      unless File.directory?(config.addon_secrets_path)
        FileUtils.mkdir_p(config.addon_secrets_path)
      end

      render_erb 'install.sh'
    end
  end

  class Kubelet
    include Porkadot::Assets
    TEMPLATE_DIR = File.join(File.dirname(__FILE__), "kubelet")

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
      unless File.directory?(config.target_path)
        FileUtils.mkdir_p(config.target_path)
      end
      unless File.directory?(config.target_secrets_path)
        FileUtils.mkdir_p(config.target_secrets_path)
      end
      ca_data = certs.ca_cert.to_pem
      ca_data = Base64.strict_encode64(ca_data)

      render_erb 'bootstrap-kubelet.conf', ca_data: ca_data
      render_bootstrap_certs
      render_erb 'config.yaml'
      render_erb 'kubelet.service'
      render_ca_crt
      render_erb 'install.sh'
      render_erb 'install-deps.sh'
      render_erb 'install-pkgs.sh'
      render_erb 'setup-containerd.sh'
    end

    def render_bootstrap_certs
      logger.info "----> bootstrap certs"
      self.bootstrap_key
      self.bootstrap_cert(true)
    end

    def render_ca_crt
      logger.info "----> ca.crt"
      open(config.ca_crt_path, 'w') do |out|
        out.write self.certs.ca_cert(false).to_pem
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
