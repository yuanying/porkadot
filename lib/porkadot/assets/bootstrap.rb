require 'fileutils'

module Porkadot; module Assets
  class Bootstrap
    include Porkadot::Assets
    TEMPLATE_DIR = File.join(File.dirname(__FILE__), "bootstrap")
    attr_reader :global_config
    attr_reader :config
    attr_reader :certs_config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @config = global_config.bootstrap
      @certs_config = global_config.certs
      @logger = global_config.logger
    end

    def render
      logger.info "--> Rendering bootstrap manifests"
      unless File.directory?(config.bootstrap_path)
        FileUtils.mkdir_p(config.bootstrap_path)
      end
      render_secrets
      render_erb 'bootstrap/kubeconfig-bootstrap.yaml'
      render_erb 'bootstrap/kube-proxy-bootstrap.yaml'
      render_manifests
      render_erb 'install.sh'
      render_erb 'cleanup.sh'
    end

    # Creates the certificates the bootstrap control plane needs when they
    # are missing, then copies them. Existing ones are kept as they are.
    def render_secrets
      logger.info "----> Secrets"
      certs = Porkadot::Assets::Certs.new(global_config)
      certs.etcd.prepare
      certs.kubernetes.prepare
      certs.front_proxy.prepare

      store = global_config.asset_store
      root = certs_config.certs_root_dir
      secret_paths.each do |src|
        rel = src.delete_prefix(root + File::SEPARATOR)
        store.copy(src, File.join(config.secrets_path, rel), secret: true)
      end
    end

    def secret_paths
      etcd = certs_config.etcd
      k8s = certs_config.kubernetes
      front_proxy = certs_config.front_proxy
      [
        etcd.ca_cert_path, etcd.ca_key_path,
        etcd.client_cert_path, etcd.client_key_path,
        k8s.ca_cert_path, k8s.ca_key_path,
        k8s.apiserver_cert_path, k8s.apiserver_key_path,
        k8s.kubelet_client_cert_path, k8s.kubelet_client_key_path,
        k8s.admin_cert_path, k8s.admin_key_path,
        k8s.sa_private_key_path, k8s.sa_public_key_path,
        front_proxy.ca_cert_path, front_proxy.ca_key_path,
        front_proxy.client_cert_path, front_proxy.client_key_path,
      ]
    end

    def render_manifests
      unless File.directory?(config.manifests_path)
        FileUtils.mkdir_p(config.manifests_path)
      end
      render_erb 'manifests/kube-apiserver.bootstrap.yaml'
      render_erb 'manifests/kube-controller-manager.bootstrap.yaml'
      render_erb 'manifests/kube-scheduler.bootstrap.yaml'
      render_erb 'manifests/kube-proxy.bootstrap.yaml'
    end

  end

end; end
