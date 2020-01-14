require 'yaml'
require 'hashie'
require 'logger'

module Porkadot
  class Config
    attr_reader :raw
    attr_reader :logger

    def initialize path
      default_config = {}
      open(File.expand_path(File.join(Porkadot::ROOT, 'porkadot', 'default.yaml'))) do |io|
        default_config = YAML::load(io)
      end
      open(File.expand_path(path)) do |io|
        @raw = ::Hashie::Mash.new(default_config.rmerge(YAML.load(io)))
      end
      @logger = Logger.new(STDOUT)
    end

    def kubernetes
      @raw.kubernetes
    end
    alias k8s kubernetes

    def nodes
      @raw.nodes
    end

    def assets_dir
      File.expand_path(raw.local.assets_dir)
    end

    def certs_dir
      File.join(self.assets_dir, 'certs')
    end

    def etcd_certs_dir
      File.join(self.certs_dir, 'etcd')
    end

    def etcd_ca_key_path
      File.join(self.etcd_certs_dir, 'ca.key')
    end

    def etcd_ca_cert_path
      File.join(self.etcd_certs_dir, 'ca.crt')
    end

    def etcd_client_key_path
      File.join(self.etcd_certs_dir, 'etcd-client.key')
    end

    def etcd_client_cert_path
      File.join(self.etcd_certs_dir, 'etcd-client.crt')
    end

    def k8s_certs_dir
      File.join(self.certs_dir, 'kubernetes')
    end

    def k8s_ca_key_path
      File.join(self.k8s_certs_dir, 'ca.key')
    end

    def k8s_ca_cert_path
      File.join(self.k8s_certs_dir, 'ca.crt')
    end

    def k8s_apiserver_key_path
      File.join(self.k8s_certs_dir, 'apiserver.key')
    end

    def k8s_apiserver_cert_path
      File.join(self.k8s_certs_dir, 'apiserver.crt')
    end

    def k8s_kubelet_client_key_path
      File.join(self.k8s_certs_dir, 'kubelet-client.key')
    end

    def k8s_kubelet_client_cert_path
      File.join(self.k8s_certs_dir, 'kubelet-client.crt')
    end

    def k8s_admin_key_path
      File.join(self.k8s_certs_dir, 'admin.key')
    end

    def k8s_admin_cert_path
      File.join(self.k8s_certs_dir, 'admin.crt')
    end

    def k8s_front_proxy_ca_key_path
      File.join(self.k8s_certs_dir, 'front-proxy-ca.key')
    end

    def k8s_front_proxy_ca_cert_path
      File.join(self.k8s_certs_dir, 'front-proxy-ca.crt')
    end

    def k8s_front_proxy_key_path
      File.join(self.k8s_certs_dir, 'front-proxy-client.key')
    end

    def k8s_front_proxy_cert_path
      File.join(self.k8s_certs_dir, 'front-proxy-client.crt')
    end

    def k8s_sa_private_key_path
      File.join(self.k8s_certs_dir, 'sa.key')
    end

    def k8s_sa_public_key_path
      File.join(self.k8s_certs_dir, 'sa.pub')
    end
  end
end
