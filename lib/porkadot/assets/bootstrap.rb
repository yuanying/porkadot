require 'fileutils'

module Porkadot; module Assets
  class Bootstrap
    include Porkadot::Assets
    TEMPLATE_DIR = File.join(File.dirname(__FILE__), "bootstrap")
    attr_reader :global_config
    attr_reader :config
    attr_reader :certs_config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @config = global_config.bootstrap
      @certs_config = global_config.certs
      @logger = global_config.logger
    end

    def render
      logger.info "--> Rendering bootstrap manifests"
      unless File.directory?(config.bootstrap_path)
        FileUtils.mkdir_p(config.bootstrap_path)
      end
      render_secrets
      render_erb 'bootstrap/kubeconfig-bootstrap.yaml'
      render_erb 'bootstrap/kube-proxy-bootstrap.yaml'
      render_manifests
      render_erb 'install.sh'
      render_erb 'cleanup.sh'
    end

    def render_secrets
      logger.info "----> Secrets"
      store = global_config.asset_store
      root = certs_config.certs_root_dir
      Dir.glob('**/*', base: root).sort.each do |rel|
        src = File.join(root, rel)
        next unless File.file?(src)
        store.copy(src, File.join(config.secrets_path, rel), secret: true)
      end
    end

    def render_manifests
      unless File.directory?(config.manifests_path)
        FileUtils.mkdir_p(config.manifests_path)
      end
      render_erb 'manifests/kube-apiserver.bootstrap.yaml'
      render_erb 'manifests/kube-controller-manager.bootstrap.yaml'
      render_erb 'manifests/kube-scheduler.bootstrap.yaml'
      render_erb 'manifests/kube-proxy.bootstrap.yaml'
    end

  end

end; end
