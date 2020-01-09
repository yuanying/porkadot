module Porkadot; module Render; module Certs
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    default_task :all
    desc "all", "Render all certificates to deploy Kubernetes cluster"
    def all
    end

    desc 'etcd', "Render certificates to deploy Etcd"
    def etcd
      puts 'etcd'
      self.config.assets_dir
    end

    desc 'kubernetes', "Render certificates to deploy Kubernetes"
    def kubernetes
      puts 'kubernetes'
    end

    def self.subcommand_prefix
      'render certs'
    end
  end
end; end; end
