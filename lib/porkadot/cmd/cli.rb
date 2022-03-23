
module Porkadot; module Cmd
  class Cli < Thor
    include Porkadot::Utils

    class_option :config, type: :string,
      default: './porkadot.yaml',
      desc: 'Path to porkadot config file'

    desc "render", "Render assets to deploy Kubernetes"
    subcommand "render", Porkadot::Cmd::Render::Cli

    desc "install", "Install kubernetes"
    subcommand "install", Porkadot::Cmd::Install::Cli

    desc "setup-containerd", "Setup containerd"
    option :node, type: :string
    option :force, type: :boolean, default: false
    def setup_containerd
      logger.info "Setup containerd"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      nodes = []
      if node = options[:node]
        nodes = kubelets[node]
      else
        nodes = kubelets.kubelets.values
      end
      kubelets.setup_containerd hosts: nodes, force: options[:force]
      ""
    end

    desc "setup-node", "Setup node default settings"
    option :node, type: :string
    option :force, type: :boolean, default: false
    def setup_node
      logger.info "Setup node default"
      kubelets = Porkadot::Install::KubeletList.new(self.config)
      nodes = []
      if node = options[:node]
        nodes = kubelets[node]
      else
        nodes = kubelets.kubelets.values
      end
      kubelets.setup_default hosts: nodes, force: options[:force]
      ""
    end

    desc "set-config", "Set cluster to kubeconfig"
    def set_config
      name = config.k8s.cluster_name
      certs = Porkadot::Assets::Certs.new(config)
      `kubectl config set-cluster #{name} \
        --server=https://#{config.k8s.control_plane_endpoint}`
      `kubectl config set \
        clusters.#{name}.certificate-authority-data \
        "#{certs.kubernetes.to_base64(:ca_cert)}"`
      `kubectl config set-credentials #{name}-admin`
      `kubectl config set \
        users.#{name}-admin.client-certificate-data \
        "#{certs.kubernetes.to_base64(:client_cert)}"`
      `kubectl config set \
        users.#{name}-admin.client-key-data \
        "#{certs.kubernetes.to_base64(:client_key)}"`
      `kubectl config set-context #{name} \
        --cluster=#{name} \
        --user=#{name}-admin`
      `kubectl config use-context #{name}`
    end

    default_task :all
    desc "all", "Render and install Kubernetes cluster"
    def all
      invoke :render, [], options
      invoke :install, [], options
    end
  end
end; end
