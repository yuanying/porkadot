
module Porkadot; module Cmd; module Install; module Bootstrap
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    def initialize(*arg)
      super
    end

    default_task :all
    desc "all", "Install all bootstrap components"
    def all
      invoke :node
      invoke :kubernetes
    end

    desc "node", "Install bootstrap node"
    def node
      logger.info "Installing bootstrap node"
      bootstrap = Porkadot::Install::Bootstrap.new(self.config)
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      kubelets.install hosts: [bootstrap.host]
      bootstrap.install
      ""
    end

    desc "kubernetes", "Install bootstrap kubernetes"
    def kubernetes
      logger.info "Installing bootstrap kubernetes"
    end

    def self.subcommand_prefix
      'install bootstrap'
    end
  end

end; end; end; end
