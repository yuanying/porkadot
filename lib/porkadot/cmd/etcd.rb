
module Porkadot; module Cmd; module Etcd
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    default_task :all
    desc "all", "Interact with etcd"
    def all
      "Use restore or backup sub commands."
    end

    desc "backup", "Backup etcd data"
    option :node, type: :string
    option :path, type: :string, default: "./backup", desc: "Directory where etcd backup data will be stored."
    def backup
      require 'date'

      filename = "etcd-#{DateTime.now.to_s}.db"
      path = File.join(options[:path], filename)

      logger.info "Backing up etcd data to #{path}"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      kubelets.backup_etcd host: options[:node], path: path
      ""
    end

    def self.subcommand_prefix
      'etcd'
    end
  end
end; end; end

