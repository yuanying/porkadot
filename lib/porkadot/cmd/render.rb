
module Porkadot; module Cmd; module Render
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    default_task :all
    desc "all", "Render all assets to deploy Kubernetes cluster"
    def all
      invoke "porkadot:cmd:render:certs:cli:all", [], options
      invoke :kubelet, [], options
    end

    desc "certs", "Render certificates to deploy Kubernetes"
    subcommand "certs", Porkadot::Cmd::Render::Certs::Cli

    desc "kubelet", "Render kubelet related files"
    def kubelet
      logger.info "Generating kubelet related files"
      Porkadot::Assets::KubeletList.new(self.config).render
      ""
    end

    def self.subcommand_prefix
      'render'
    end
  end
end; end; end
