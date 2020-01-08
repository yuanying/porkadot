require 'porkadot/config'
require 'porkadot/render'

module Porkadot
  class Cli < Thor
    class_option :config, type: :string,
      default: '~/.kube/porkadot.yaml',
      desc: 'Modify porkadot config file'

    desc "render", "Render assets to deploy Kubernetes"
    subcommand "render", Porkadot::Render::Cli
  end
end
