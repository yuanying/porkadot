module Porkadot; module Cmd; module RotateCerts
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    default_task :all

    desc "all", "Rotate all rendered cluster certificates"
    option :node, type: :string
    def all
      logger.info "Rotating certificates"
      installer.all(node: options[:node])
      ""
    end

    desc "etcd", "Rotate etcd certificates"
    option :node, type: :string
    def etcd
      logger.info "Rotating etcd certificates"
      installer.etcd(node: options[:node])
      ""
    end

    desc "kubernetes", "Rotate Kubernetes control plane certificates"
    option :node, type: :string
    def kubernetes
      logger.info "Rotating Kubernetes certificates"
      installer.kubernetes(node: options[:node])
      ""
    end

    desc "kubelet-ca", "Rotate Kubernetes CA bundle on kubelet nodes"
    option :node, type: :string
    def kubelet_ca
      logger.info "Rotating kubelet CA bundle"
      installer.kubelet_ca(node: options[:node])
      ""
    end

    def self.subcommand_prefix
      'rotate-certs'
    end

    private

    def installer
      @installer ||= Porkadot::Install::RotateCerts.new(config)
    end
  end
end; end; end
