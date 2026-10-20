
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
      logger.info "Stop etcd"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      kubelets.stop_etcd hosts: options[:node]
      ""
    end

    desc "restore", "Restore etcd data"
    option :path, type: :string, default: "./backup", desc: "Directory where etcd backup data is stored."
    option :timeout, type: :numeric, default: Porkadot::Install::KubeletList::DEFAULT_RESTORE_TIMEOUT,
      desc: "Seconds to wait for etcd and for each control plane component after the restore"
    option :bump_revision, type: :numeric,
      desc: "How far to move the etcd revision. By default it goes 1000000000 past the current revision, read from the running etcd"
    def restore
      path = Dir.glob(File.join(options[:path], "etcd-*.db")).sort.reverse[0]
      unless path
        return "No backup data found...: #{options[:path]}"
      end

      kubelets = Porkadot::Install::KubeletList.new(self.config)
      bump_revision = options[:bump_revision]&.to_i
      if bump_revision && bump_revision <= 0
        raise Porkadot::Error, "--bump-revision must be positive: #{options[:bump_revision]}"
      end
      current_revision = nil
      # Only the running etcd knows the revision clients have seen.
      if self.config.etcd.restore_bumps_revision? && !bump_revision
        current_revision = kubelets.current_etcd_revision
        unless current_revision
          raise Porkadot::Error, "Could not read the current revision from any etcd member, and etcd is left running. " \
            "Give the amount to move the revision by with --bump-revision. It has to be larger than the " \
            "highest revision any client has seen minus the snapshot's revision (etcdutl snapshot status)."
        end
      end

      invoke :stop, [], options

      logger.info "Restore etcd from #{path}"
      kubelets.restore_etcd path: path, current_revision: current_revision, bump_revision: bump_revision

      invoke :start, [], options

      # Clients that keep running would go on with what they had before the
      # restore. The bumped and compacted revision makes their watches list
      # again; the control plane is also replaced, as Kubernetes recommends.
      logger.info "Waiting for etcd"
      kubelets.wait_etcd_health timeout: options[:timeout]
      logger.info "Restarting kube-apiserver, kube-controller-manager and kube-scheduler"
      kubelets.restart_control_plane timeout: options[:timeout]
      ""
    end

    def self.subcommand_prefix
      'etcd'
    end

    no_commands do
      # etcd backup/restore do not read rendered assets, and must keep
      # working while the assets are being migrated.
      def assets_layout_check?
        false
      end
    end
  end
end; end; end

