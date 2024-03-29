require 'ipaddr'

module Porkadot; module Configs

  module CertsUtils

    def certs_root_dir
      File.join(self.config.secrets_root_dir, 'certs')
    end

    def ipaddr?(addr)
      if addr.nil?
        return false
      end
      IPAddr.new(addr)
      return true
    rescue IPAddr::InvalidAddressError
      return false
    end

  end

  class Certs
    include CertsUtils
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

end; end

require 'porkadot/configs/certs/etcd'
require 'porkadot/configs/certs/k8s'
require 'porkadot/configs/certs/front_proxy'
