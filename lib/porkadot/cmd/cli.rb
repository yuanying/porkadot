
module Porkadot; module Cmd
  class Cli < Thor
    include Porkadot::Utils

    class_option :config, type: :string,
      default: '~/.kube/porkadot.yaml',
      desc: 'Path to porkadot config file'

    desc "render", "Render assets to deploy Kubernetes"
    subcommand "render", Porkadot::Cmd::Render::Cli

    desc "install", "Install kubernetes"
    subcommand "install", Porkadot::Cmd::Install::Cli

    default_task :all
    desc "all", "Render and install Kubernetes cluster"
    def all
    end
  end
end; end
