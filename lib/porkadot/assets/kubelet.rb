require 'fileutils'
require 'erb'
require 'base64'

module Porkadot; module Assets
  class KubeletList
    attr_reader :config
    attr_reader :logger

    def initialize config
      @config = config
      @logger = config.logger
    end

    def render
      config.nodes.each do |k, node|
        Kubelet.new(config, k, node).render
      end
    end
  end

  class Kubelet
    KUBELETE_TEMPLATE_DIR = File.join(File.dirname(__FILE__), "kubelet")

    attr_reader :config
    attr_reader :logger
    attr_reader :name
    attr_reader :node
    attr_reader :certs
    attr_reader :assets
    attr_reader :cert_assets

    def initialize config, name, node
      @config = config
      @logger = config.logger
      @name = name
      @node = node
      @assets = Porkadot::Assets::Kubelet.new(config, name, node)
      @cert_assets = Porkadot::Assets::Certs.new(config)
      @certs = Porkadot::Certs.new(config)
    end

    def render
      logger.info "--> Rendering #{name} node"
      unless File.directory?(assets.kubelet_path)
        FileUtils.mkdir_p(assets.kubelet_path)
      end
      render_bootstrap_kubeconfig
    end

    def render_bootstrap_kubeconfig
      logger.info "----> bootstrap kubeconfig"
      ca_data = open(cert_assets.k8s_ca_cert_path) {|io| io.read }
      open(File.join(KUBELETE_TEMPLATE_DIR, 'bootstrap-kubelet.conf.erb')) do |io|
        open(assets.bootstrap_kubeconfig_path, 'w') do |out|
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            node: node,
            ca_data: Base64.strict_encode64(ca_data)
          )
        end
      end
    end

    def render_bootstrap_certs
      logger.info "----> bootstrap private key"
      bootstrap_client_key = self.private_key(self.assets.bootstrap_key_path)
      self.client_cert(self.assets.bootstrap_cert_path, '/O=porkadot:node-bootstrappers/CN=node-bootstrapper:#{name}', bootstrap_client_key, ca_cert, ca_key)
    end
  end
end; end
