require 'fileutils'
require 'erb'

module Porkadot; module Assets
  class Kubernetes
    include Porkadot::Assets
    TEMPLATE_DIR = File.join(File.dirname(__FILE__), "kubernetes")
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @config = global_config.kubernetes
      @logger = global_config.logger
    end

    def render
      logger.info "--> Rendering kubernetes manifests"
      unless File.directory?(config.manifests_path)
        FileUtils.mkdir_p(config.manifests_path)
      end
      lb = global_config.lb
      render_erb 'manifests/kubelet.yaml'
      render_erb "manifests/#{lb.type}.yaml"
      render_erb "manifests/#{lb.type}-config.yaml"
      render_erb 'install.sh'
    end

  end
end; end
