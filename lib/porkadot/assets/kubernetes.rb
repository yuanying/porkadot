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
      render_erb 'manifests/porkadot.yaml'
      render_erb 'manifests/kubelet.yaml'
      render_erb "manifests/kube-apiserver.yaml"
      render_secrets_erb "manifests/kube-apiserver.secrets.yaml"
      render_erb "manifests/kube-proxy.yaml"
      render_erb "manifests/kube-scheduler.yaml"
      render_erb "manifests/kube-controller-manager.yaml"
      render_secrets_erb "manifests/kube-controller-manager.secrets.yaml"
      render_secrets_erb "kubeconfig.yaml"
      render_erb 'manifests/kustomization.yaml'
      render_erb 'kustomization.yaml'
      render_erb 'install.sh'
      render_secrets_erb 'install.secrets.sh'

      addons = Addons.new(global_config)
      addons.render
    end
  end

  class Addons
    include Porkadot::Assets
    TEMPLATE_DIR = File.join(File.dirname(__FILE__), "kubernetes", "manifests", "addons")
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @config = global_config.addons
      @logger = global_config.logger
    end

    def render
      logger.info "--> Rendering kubernetes addons"
      render_erb "kustomization.yaml"

      self.config.enabled.each do |name|
        manifests = @@manifests[name]
        manifests.each do |m|
          render_erb(m)
        end
        secrets = @@secrets_manifests[name]
        secrets.each do |m|
          render_secrets_erb(m)
        end
      end
    end

    def self.register_manifests name, manifests, secrets: []
      @@manifests ||= {}
      @@manifests[name] = manifests
      @@secrets_manifests ||= {}
      @@secrets_manifests[name] = secrets
    end

    register_manifests('flannel', [
      'flannel/flannel.yaml',
      'flannel/kustomization.yaml'
    ])

    register_manifests('coredns', [
      'coredns/coredns.yaml',
      'coredns/dns-horizontal-autoscaler.yaml',
      'coredns/kustomization.yaml'
    ])

    register_manifests('metallb', [
      'metallb/000-metallb.yaml',
      'metallb/metallb.yaml',
      'metallb/metallb.config.yaml',
      'metallb/kustomization.yaml'
    ], secrets: [
      'metallb/metallb.secrets.yaml'
    ])


    register_manifests('kubelet-rubber-stamp', [
      'kubelet-rubber-stamp/kubelet-rubber-stamp.yaml',
      'kubelet-rubber-stamp/kustomization.yaml'
    ])

    register_manifests('storage-version-migrator', [
      'storage-version-migrator/storage-version-migrator.yaml',
      'storage-version-migrator/kustomization.yaml'
    ])

  end
end; end
