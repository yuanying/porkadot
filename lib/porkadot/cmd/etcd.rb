
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

    desc "start", "Start etcd"
    option :node, type: :string
    def start
      logger.info "Start etcd"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      kubelets.start_etcd hosts: options[:node]
      ""
    end

    desc "stop", "Stop etcd"
    option :node, type: :string
    def stop
      logger.info "Start etcd"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      kubelets.stop_etcd hosts: options[:node]
      ""
    end

    desc "restore", "Restore etcd data"
    option :path, type: :string, default: "./backup", desc: "Directory where etcd backup data is stored."
    def restore
      invoke :stop, [], options

      path = Dir.glob(File.join(options[:path], "etcd-*.db")).sort.reverse[0]
      unless path
        return "No backup data found...: #{options[:path]}"
      end

      logger.info "Restore etcd from #{path}"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      kubelets.restore_etcd path: path

      invoke :start, [], options
      ""
    end

    def self.subcommand_prefix
      'etcd'
    end
  end
end; end; end

