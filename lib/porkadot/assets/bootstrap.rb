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
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end
  end

end; end
