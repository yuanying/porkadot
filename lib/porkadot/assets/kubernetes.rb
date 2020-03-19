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
      unless File.directory?(config.target_path)
        FileUtils.mkdir_p(config.target_path)
      end
      render_erb 'kubelet.yaml'
      render_erb 'metallb.yaml'
    end

  end
end; end
