require 'yaml'
require 'hashie'
require 'logger'

module Porkadot
  class Config
    attr_reader :raw
    attr_reader :logger

    def initialize path
      default_config = {}
      open(File.expand_path(File.join(Porkadot::ROOT, 'porkadot', 'default.yaml'))) do |io|
        default_config = YAML::load(io)
      end
      open(File.expand_path(path)) do |io|
        @raw = ::Hashie::Mash.new(default_config.rmerge(YAML.load(io)))
      end
      @logger = Logger.new(STDOUT)
    end

    def kubernetes
      @raw.kubernetes
    end
    alias k8s kubernetes

    def nodes
      @raw.nodes
    end

    def assets_dir
      File.expand_path(raw.local.assets_dir)
    end

  end
end
