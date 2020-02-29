
module Porkadot; module Cmd; module Install
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    default_task :all
    desc "all", "Install Kubernetes cluster"
    def all
      invoke :kubelet, [], options
    end

    desc "kubelet", "Install kubelet to nodes"
    option :node, type: :string
    option :force, type: :boolean, default: false
    def kubelet
      logger.info "Installing kubelet"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      nodes = []
      if node = options[:node]
        nodes = kubelets[node]
      else
        nodes = kubelets.kubelets.values
      end
      kubelets.install hosts: nodes, force: options[:force]
      ""
    end

    def self.subcommand_prefix
      'install'
    end
  end
end; end; end
