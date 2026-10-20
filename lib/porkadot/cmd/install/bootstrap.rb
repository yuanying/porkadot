
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
      invoke :cleanup
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
      bootstrap = Porkadot::Install::Bootstrap.new(self.config)
      k8s = Porkadot::Install::Kubernetes.new(self.config)
      # The self-hosted apiservers become ready only once the rest is applied.
      k8s.install(bootstrap.host, wait_apiserver: false)
      ""
    end

    desc "cleanup", "Cleanup bootstrap node"
    option :timeout, type: :numeric, default: Porkadot::Install::Bootstrap::DEFAULT_CLEANUP_TIMEOUT,
      desc: "Seconds to wait for the self-hosted control plane before giving up"
    def cleanup
      logger.info "Cleanup bootstrap node"
      bootstrap = Porkadot::Install::Bootstrap.new(self.config)
      bootstrap.cleanup(timeout: options[:timeout])
      ""
    end

    def self.subcommand_prefix
      'install bootstrap'
    end
  end

end; end; end; end
