module Porkadot; module Render; module Certs
  class Cli < Porkadot::SubCommandBase
    desc 'etcd', "Render certificates to deploy Etcd"
    def etcd
      puts 'etcd'
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
