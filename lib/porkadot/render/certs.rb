module Porkadot; module Render; module Certs
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils
    include Porkadot::Certs

    default_task :all
    desc "all", "Render all certificates to deploy Kubernetes cluster"
    def all
      invoke :etcd
      invoke :kubernetes
    end

    desc 'etcd', "Render certificates to deploy Etcd"
    def etcd
      logger.info "Generating etcd certificates"
      logger.info "--> CA key and certs"
      ca_key = self.private_key(self.config.etcd_ca_key_path)
      ca_cert = self.ca_cert(self.config.etcd_ca_cert_path, '/CN=kube-ca', ca_key)
      logger.info "--> Client key and certs"
      client_key = self.private_key(self.config.etcd_client_key_path)
      client_cert = self.client_cert(self.config.etcd_client_cert_path, '/CN=etcd-client', client_key, ca_cert, ca_key)
      ''
    end

    desc 'kubernetes', "Render certificates to deploy Kubernetes"
    def kubernetes
      logger.info "Generating kubernetes certificates"
      logger.info "--> CA key and certs"
      ca_key = self.private_key(self.config.k8s_ca_key_path)
      ca_cert = self.ca_cert(self.config.k8s_ca_cert_path, '/CN=kube-ca', ca_key)
      logger.info "--> API server key and certs"
      apiserver_key = self.private_key(self.config.k8s_apiserver_key_path)
      self.apiserver_cert(self.config.k8s_apiserver_cert_path, apiserver_key, ca_cert, ca_key)
      logger.info "--> Kubelet client key and certs"
      kubelet_client_key = self.private_key(self.config.k8s_kubelet_client_key_path)
      self.client_cert(self.config.k8s_kubelet_client_cert_path, '/O=system:masters/CN=kube-kubelet-client', kubelet_client_key, ca_cert, ca_key)
      logger.info "--> Admin client key and certs"
      admin_client_key = self.private_key(self.config.k8s_admin_key_path)
      self.client_cert(self.config.k8s_admin_cert_path, '/O=system:masters/CN=admin', admin_client_key, ca_cert, ca_key)
      logger.info "--> Front-proxy CA key and certs"
      front_proxy_ca_key = self.private_key(self.config.k8s_front_proxy_ca_key_path)
      front_proxy_ca_cert = self.ca_cert(self.config.k8s_front_proxy_ca_cert_path, '/CN=front-proxy-ca', front_proxy_ca_key)
      logger.info "--> Front-proxy client key and certs"
      front_proxy_key = self.private_key(self.config.k8s_front_proxy_key_path)
      self.client_cert(self.config.k8s_front_proxy_cert_path, '/CN=aggregator-client', front_proxy_key, front_proxy_ca_cert, front_proxy_ca_key)
      logger.info "--> Private key for signing service account tokens"
      sa_private_key = self.private_key(self.config.k8s_sa_private_key_path)
      self.public_key(self.config.k8s_sa_public_key_path, sa_private_key)
      ''
    end

    def self.subcommand_prefix
      'render certs'
    end
  end
end; end; end
