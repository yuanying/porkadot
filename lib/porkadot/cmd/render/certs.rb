require 'forwardable'

module Porkadot; module Cmd; module Render; module Certs
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils

    def initialize(*arg)
      super
    end

    default_task :all
    desc "all", "Render all certificates to deploy Kubernetes cluster"
    def all
      invoke :etcd
      invoke :kubernetes
    end

    desc 'etcd', "Render certificates to deploy Etcd"
    def etcd
      logger.info "Generating etcd certificates"
      certs = Porkadot::Assets::Certs.new(config).etcd
      logger.info "--> CA key and certs"
      certs.ca_key
      certs.ca_cert(true)
      logger.info "--> Client key and certs"
      certs.client_key
      certs.client_cert(true)
      ''
    end

    desc 'kubernetes', "Render certificates to deploy Kubernetes"
    def kubernetes
      logger.info "Generating kubernetes certificates"
      certs = Porkadot::Assets::Certs.new(config).kubernetes
      logger.info "--> CA key and certs"
      certs.ca_key
      certs.ca_cert(true)
      logger.info "--> API server key and certs"
      certs.apiserver_key
      certs.apiserver_cert(true)
      logger.info "--> Kubelet client key and certs"
      certs.kubelet_client_key
      certs.kubelet_client_cert
      # logger.info "--> Bootstrap client key and certs"
      # bootstrap_client_key = self.private_key(self.assets.k8s_bootstrap_key_path)
      # self.client_cert(self.assets.k8s_bootstrap_cert_path, '/O=porkadot:node-bootstrappers/CN=node-bootstrapper', bootstrap_client_key, ca_cert, ca_key)
      logger.info "--> Admin client key and certs"
      certs.client_key
      certs.client_cert(true)
      logger.info "--> Private key for signing service account tokens"
      certs.sa_private_key
      certs.sa_public_key

      front_proxy_certs = Porkadot::Assets::Certs.new(config).front_proxy
      logger.info "--> Front-proxy CA key and certs"
      front_proxy_certs.ca_key
      front_proxy_certs.ca_cert(true)
      logger.info "--> Front-proxy client key and certs"
      front_proxy_certs.client_key
      front_proxy_certs.client_cert(true)
      ''
    end

    def self.subcommand_prefix
      'render certs'
    end
  end
end; end; end; end
