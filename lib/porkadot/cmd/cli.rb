
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
