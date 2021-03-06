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
      unless File.directory?(config.manifests_path)
        FileUtils.mkdir_p(config.manifests_path)
      end
      unless File.directory?(config.manifests_secrets_path)
        FileUtils.mkdir_p(config.manifests_secrets_path)
      end
      lb = global_config.lb
      cni = global_config.cni
      render_erb 'manifests/porkadot.yaml'
      render_erb 'manifests/kubelet.yaml'
      render_erb "manifests/#{lb.type}.yaml"
      render_secrets_erb "manifests/#{lb.type}.secrets.yaml"
      render_erb "manifests/#{cni.type}.yaml"
      render_erb "manifests/coredns.yaml"
      render_erb "manifests/dns-horizontal-autoscaler.yaml"
      render_erb "manifests/kube-apiserver.yaml"
      render_secrets_erb "manifests/kube-apiserver.secrets.yaml"
      render_erb "manifests/kube-proxy.yaml"
      render_erb "manifests/kube-scheduler.yaml"
      render_erb "manifests/kube-controller-manager.yaml"
      render_secrets_erb "manifests/kube-controller-manager.secrets.yaml"
      render_erb "manifests/pod-checkpointer.yaml"
      render_erb "manifests/kubelet-rubber-stamp.yaml"
      render_erb "manifests/storage-version-migrator.yaml"
      render_erb 'install.sh'
    end

  end
end; end
