
module Porkadot; module Cmd; module Install; module Kubernetes
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    def initialize(*arg)
      super
    end

    no_commands do
      def install target=''
        kubelets = Porkadot::Install::KubeletList.new(self.config)
        if node = options[:node]
          nodes = kubelets[node]
        else
          nodes = Porkadot::Install::Bootstrap.new(self.config).host
        end
        k8s = Porkadot::Install::Kubernetes.new(self.config)
        k8s.install(nodes, target)
        ""
      end
    end

    default_task :all
    desc "all", "Install all components"
    option :node, type: :string
    def all
      logger.info "Installing kubernetes"
      self.install
    end

    desc "apiserver", "Install apiserver"
    option :node, type: :string
    def apiserver
      logger.info "Installing kube-apiserver"
      self.install 'kube-apiserver'
    end

    desc "controller-manager", "Install controller-manager"
    option :node, type: :string
    def controller_manager
      logger.info "Installing kube-controller-manager"
      self.install 'kube-controller-manager'
    end

    desc "scheduler", "Install scheduler"
    option :node, type: :string
    def scheduler
      logger.info "Installing kube-scheduler"
      self.install 'kube-scheduler'
    end

    desc "proxy", "Install proxy"
    option :node, type: :string
    def proxy
      logger.info "Installing kube-proxy"
      self.install 'kube-proxy'
    end

    def self.subcommand_prefix
      'install kubernetes'
    end
  end

end; end; end; end

