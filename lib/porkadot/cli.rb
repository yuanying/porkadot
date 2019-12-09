require 'porkadot/render'

module Porkadot
  class Cli < Thor
    desc "render", "Render assets to deploy Kubernetes"
    subcommand "render", Porkadot::Render::Cli
  end
end
