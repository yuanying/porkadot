
module Porkadot; module Cmd; module Render
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    default_task :all
    desc "all", "Render all assets to deploy Kubernetes cluster"
    def all
      invoke "porkadot:cmd:render:certs:cli:all", [], options
      invoke :kubelet, [], options
      invoke :etcd, [], options
      invoke :bootstrap, [], options
      invoke :kubernetes, [], options
    end

    desc "certs", "Render certificates to deploy Kubernetes"
    subcommand "certs", Porkadot::Cmd::Render::Certs::Cli

    desc "kubelet", "Render kubelet related files"
    option :node, type: :string
    def kubelet
      logger.info "Generating kubelet related files"
      kubelets = Porkadot::Assets::KubeletList.new(self.config)
      if node = options[:node]
        kubelets[node].render
      else
        kubelets.render
      end
      ""
    end

    desc "etcd", "Render etcd related files"
    option :node, type: :string
    def etcd
      logger.info "Generating etcd related files"
      etcds = Porkadot::Assets::EtcdList.new(self.config)
      if node = options[:node]
        etcds[node].render
      else
        etcds.render
      end
      ""
    end

    desc "bootstrap", "Render bootstrap related files"
    def bootstrap
      logger.info "Generating bootstrap related files"
      bootstrap = Porkadot::Assets::Bootstrap.new(self.config)
      kubelet = Porkadot::Assets::Kubelet.new(self.config.bootstrap.kubelet_config)
      kubelet.render
      bootstrap.render
      ""
    end

    desc "kubernetes", "Render kubernetes manifests"
    def kubernetes
      logger.info "Generating kubernetes manifests"
      k8s = Porkadot::Assets::Kubernetes.new(self.config)
      k8s.render
      ""
    end

    def self.subcommand_prefix
      'render'
    end
  end
end; end; end
