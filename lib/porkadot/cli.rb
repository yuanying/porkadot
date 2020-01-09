require 'porkadot/config'
require 'porkadot/render'

module Porkadot
  class Cli < Thor
    include Porkadot::Utils

    class_option :config, type: :string,
      default: '~/.kube/porkadot.yaml',
      desc: 'Path to porkadot config file'

    desc "render", "Render assets to deploy Kubernetes"
    subcommand "render", Porkadot::Render::Cli

    default_task :all
    desc "all", "Render and install Kubernetes cluster"
    def all
    end
  end
end
