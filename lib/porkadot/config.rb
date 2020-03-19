require 'yaml'
require 'hashie'
require 'logger'

module Porkadot
  class Raw < ::Hashie::Mash
    disable_warnings :keys
  end

  class Config
    attr_reader :raw
    attr_reader :logger

    def initialize path
      default_config = {}
      open(File.expand_path(File.join(Porkadot::ROOT, 'porkadot', 'default.yaml'))) do |io|
        default_config = YAML::load(io)
      end
      open(File.expand_path(path)) do |io|
        @raw = ::Porkadot::Raw.new(default_config.rmerge(YAML.load(io)))
      end
      @logger = Logger.new(STDOUT)
    end

    def certs
      @certs ||= Porkadot::Configs::Certs.new(self)
      return @certs
    end

    def connection
      self.raw.connection
    end

    def bootstrap
      @bootstrap ||= Porkadot::Configs::Bootstrap.new(self)
      return @bootstrap
    end

    def kubernetes
      @kubernetes ||= Porkadot::Configs::Kubernetes.new(self)
      return @kubernetes
    end
    alias k8s kubernetes

    def etcd
      @etcd ||= Porkadot::Configs::Etcd.new(self)
      return @etcd
    end

    def nodes
      @nodes ||= {}.tap do |nodes|
        self.raw.nodes.each do |k, v|
          nodes[k] = Porkadot::Configs::Kubelet.new(self, k, v)
        end
      end
      return @nodes
    end

    def etcd_nodes
      @etcd_nodes ||= {}.tap do |nodes|
        self.raw.nodes.each do |k, v|
          if v && v.labels && v.labels.to_hash.keys.include?(Porkadot::ETCD_MEMBER_LABEL)
            nodes[k] = Porkadot::Configs::EtcdNode.new(self, k, v)
          end
        end
      end
      return @etcd_nodes
    end

    def assets_dir
      File.expand_path(raw.local.assets_dir)
    end

  end

  module ConfigUtils

    def asset_path file
      File.join(self.target_path, file.to_s)
    end
    alias path asset_path

    def method_missing name, *args
      return nil if self.raw.nil?
      self.raw[name]
    end

    def respond_to_missing? sym, include_private
      return false if self.raw.nil?
      self.raw.respond_to_missing?(sym, include_private) ? true : super
    end
  end
end
