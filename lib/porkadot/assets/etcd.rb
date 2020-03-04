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
        @nodes[k] = Etcd.new(config)
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

  class Etcd
    ETCD_TEMPLATE_DIR = File.join(File.dirname(__FILE__), "etcd")

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
      unless File.directory?(config.etcd_path)
        FileUtils.mkdir_p(config.etcd_path)
      end
      render_install_sh
    end

    def render_install_sh
      logger.info "----> install.sh"
      open(File.join(ETCD_TEMPLATE_DIR, 'install.sh.erb')) do |io|
        open(config.install_sh_path, 'w') do |out|
          out.write ERB.new(io.read).result_with_hash(
            config: config,
            global_config: global_config,
          )
        end
      end
    end

  end
end; end
