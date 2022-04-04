require 'forwardable'

module Porkadot; module Cmd; module Render; module Manifests
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    def initialize(*arg)
      super
    end

    default_task :all
    desc "all", "Render all certificates to deploy Kubernetes cluster"
    def all
      invoke :kubernetes
    end

    desc "kubernetes", "Render kubernetes manifests"
    def kubernetes
      logger.info "Generating kubernetes manifests"
      k8s = Porkadot::Assets::Kubernetes.new(self.config)
      k8s.render
      ""
    end

    def self.subcommand_prefix
      'render manifests'
    end
  end
end; end; end; end

