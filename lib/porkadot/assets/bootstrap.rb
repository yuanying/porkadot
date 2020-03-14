require 'fileutils'

module Porkadot; module Assets
  class Bootstrap
    BOOTSTRAP_TEMPLATE_DIR = File.join(File.dirname(__FILE__), "bootstrap")
    attr_reader :global_config
    attr_reader :config
    attr_reader :certs_config
    attr_reader :logger
    attr_reader :node

    def initialize global_config
      @global_config = global_config
      @config = global_config.bootstrap
      @certs_config = global_config.certs
      @logger = global_config.logger
      @node = global_config.nodes[global_config.nodes.keys[0]]
    end

    def render
      logger.info "--> Rendering bootstrap manifests"
      unless File.directory?(config.bootstrap_path)
        FileUtils.mkdir_p(config.bootstrap_path)
      end
      render_secrets
      render_kubeconfig
      render_manifests
    end

    def render_secrets
      logger.info "----> Secrets"
      unless File.directory?(config.secrets_path)
        FileUtils.mkdir_p(config.secrets_path)
      end
      FileUtils.cp_r(Dir.glob(File.join(certs_config.certs_root_dir, '*')), config.secrets_path)
    end

    def render_kubeconfig
      logger.info "----> bootstrap kubeconfig"
      open(File.join(BOOTSTRAP_TEMPLATE_DIR, 'kubeconfig-bootstrap.yaml.erb')) do |io|
        open(config.kubeconfig_path, 'w') do |out|
          out.write ERB.new(io.read, trim_mode: '-').result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end

    def render_manifests
      unless File.directory?(config.manifests_path)
        FileUtils.mkdir_p(config.manifests_path)
      end
      render_apiserver
    end

    def render_apiserver
      logger.info "----> kube-apiserver"
      open(File.join(BOOTSTRAP_TEMPLATE_DIR, 'kube-apiserver.bootstrap.yaml.erb')) do |io|
        open(config.apiserver_path, 'w') do |out|
          out.write ERB.new(io.read, trim_mode: '-').result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end
  end

end; end
