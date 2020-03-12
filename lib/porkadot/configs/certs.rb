require 'ipaddr'

module Porkadot; module Configs

  class Certs
    attr_reader :config
    attr_reader :logger

    def initialize config
      @config = config
      @logger = config.logger
    end

    def etcd
      @etcd ||= ::Porkadot::Configs::Certs::Etcd.new(config)
      return @etcd
    end

    def kubernetes
      @kubernetes ||= ::Porkadot::Configs::Certs::Kubernetes.new(config)
      return @kubernetes
    end

    def front_proxy
      @front_proxy ||= ::Porkadot::Configs::Certs::FrontProxy.new(config)
      return @front_proxy
    end
  end

  module CertsUtils

    def certs_root_dir
      File.join(self.config.assets_dir, 'certs')
    end

    def ipaddr?(addr)
      IPAddr.new(addr)
      return true
    rescue IPAddr::InvalidAddressError
      return false
    end

  end
end; end

require 'porkadot/configs/certs/etcd'
require 'porkadot/configs/certs/k8s'
require 'porkadot/configs/certs/front_proxy'
