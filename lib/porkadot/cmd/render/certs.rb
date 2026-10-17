require 'forwardable'

module Porkadot; module Cmd; module Render; module Certs
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    def initialize(*arg)
      super
    end

    default_task :all
    class_option :ca, type: :boolean, default: true, desc: 'Render CA certificates'
    desc "all", "Render all certificates to deploy Kubernetes cluster"
    def all
      invoke :etcd, [], options
      invoke :kubernetes, [], options
    end

    desc 'etcd', "Render certificates to deploy Etcd"
    def etcd
      logger.info "Generating etcd certificates"
      certs = Porkadot::Assets::Certs.new(config)
      certs.etcd.prepare(refresh_ca: options[:ca], refresh: true)
      ''
    end

    desc 'kubernetes', "Render certificates to deploy Kubernetes"
    def kubernetes
      logger.info "Generating kubernetes certificates"
      certs = Porkadot::Assets::Certs.new(config)
      certs.kubernetes.prepare(refresh_ca: options[:ca], refresh: true)
      logger.info "Generating front-proxy certificates"
      certs.front_proxy.prepare(refresh_ca: options[:ca], refresh: true)
      ''
    end

    def self.subcommand_prefix
      'render certs'
    end
  end
end; end; end; end
