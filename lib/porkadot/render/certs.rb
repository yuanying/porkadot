module Porkadot; module Render; module Certs
  class Cli < Porkadot::SubCommandBase
    include Porkadot::Utils
    include Porkadot::Certs

    default_task :all
    desc "all", "Render all certificates to deploy Kubernetes cluster"
    def all
      self.etcd
      self.kubernetes
    end

    desc 'etcd', "Render certificates to deploy Etcd"
    def etcd
      logger.info "Generating etcd certificates"
      logger.info "--> CA key and certs"
      ca_key = self.private_key(self.config.etcd_ca_key_path)
      ca_cert = self.ca_cert(self.config.etcd_ca_cert_path, 'kube-ca', ca_key)
      logger.info "--> Client key and certs"
      client_key = self.private_key(self.config.etcd_client_key_path)
      client_cert = self.client_cert(self.config.etcd_client_cert_path, 'etcd-client', client_key, ca_cert, ca_key)
      ''
    end

    desc 'kubernetes', "Render certificates to deploy Kubernetes"
    def kubernetes
      logger.info "Generating kubernetes certificates"
      logger.info "--> CA key and certs"
      ca_key = self.private_key(self.config.k8s_ca_key_path)
      ca_cert = self.ca_cert(self.config.k8s_ca_cert_path, 'kube-ca', ca_key)
      apiserver_key = self.private_key(self.config.k8s_apiserver_key_path)
      apiserver_cert = self.apiserver_cert(self.config.k8s_apiserver_cert_path, 'apiserver', apiserver_key, ca_cert, ca_key)
      ''
    end

    def self.subcommand_prefix
      'render certs'
    end
  end
end; end; end
