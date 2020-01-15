require 'porkadot/render/certs'

module Porkadot; module Render
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    default_task :all
    desc "all", "Render all assets to deploy Kubernetes cluster"
    def all
      invoke "porkadot:render:certs:cli:all", [], options
      invoke :kubelet, [], options
    end

    desc "certs", "Render certificates to deploy Kubernetes"
    subcommand "certs", Porkadot::Render::Certs::Cli

    desc "kubelet", "Render kubelet related files"
    def kubelet
    end

    def self.subcommand_prefix
      'render'
    end
  end
end; end
