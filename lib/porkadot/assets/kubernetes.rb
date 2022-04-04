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
      unless File.directory?(File.join(config.manifests_path, 'secrets'))
        FileUtils.mkdir_p(File.join(config.manifests_path, 'secrets'))
      end
      lb = global_config.lb
      cni = global_config.cni
      render_erb 'manifests/porkadot.yaml'
      render_erb 'manifests/kubelet.yaml'
      render_erb "manifests/000-#{lb.type}.yaml"
      render_erb "manifests/#{lb.type}.yaml"
      render_erb "manifests/#{lb.type}.config.yaml"
      render_erb "manifests/secrets/#{lb.type}.yaml"
      render_erb "manifests/#{cni.type}.yaml"
      render_erb "manifests/coredns.yaml"
      render_erb "manifests/dns-horizontal-autoscaler.yaml"
      render_erb "manifests/kube-apiserver.yaml"
      render_erb "manifests/secrets/kube-apiserver.yaml"
      render_erb "manifests/kube-proxy.yaml"
      render_erb "manifests/kube-scheduler.yaml"
      render_erb "manifests/kube-controller-manager.yaml"
      render_erb "manifests/secrets/kube-controller-manager.yaml"
      render_erb "manifests/kubelet-rubber-stamp.yaml"
      render_erb "manifests/storage-version-migrator.yaml"
      render_secrets_erb "kubeconfig.yaml"
      render_erb 'manifests/kustomization.yaml'
      render_erb 'kustomization.yaml'
      render_erb 'install.sh'
    end

  end
end; end
