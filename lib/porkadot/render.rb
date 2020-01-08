require 'porkadot/render/certs'

module Porkadot; module Render
  class Cli < Porkadot::SubCommandBase
    desc "certs", "Render certificates to deploy Kubernetes"
    subcommand "certs", Porkadot::Render::Certs::Cli

    def self.subcommand_prefix
      'render'
    end
  end
end; end
