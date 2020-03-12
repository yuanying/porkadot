
module Porkadot; module Configs
  class Etcd
    include Porkadot::ConfigUtils
    attr_reader :config
    attr_reader :logger
    attr_reader :raw

    def initialize config
      @config = config
      @logger = config.logger
      @raw = config.raw.etcd
    end

  end

  class EtcdNode
    include Porkadot::ConfigUtils
    include Porkadot::Configs::CertsUtils
    attr_reader :config
    attr_reader :kubelet
    attr_reader :logger
    attr_reader :name
    attr_reader :raw

    def initialize config, name, raw
      @config = config
      @logger = config.logger
      @kubelet = config.nodes[name]
      @name = name
      @raw = raw || ::Porkadot::Raw.new
    end

    def member_name
      return (self.raw.labels && self.raw.labels[Porkadot::ETCD_MEMBER_LABEL]) || self.raw.hostname || self.name
    end

    def member_address
      return (self.raw.labels && self.raw.labels[Porkadot::ETCD_ADDRESS_LABEL]) || self.raw.hostname || self.name
    end

    def advertise_client_urls
     ["https://#{member_address}:2379"]
    end

    def advertise_peer_urls
      ["https://#{member_address}:2380"]
    end

    def listen_client_urls
      self.advertise_client_urls + ["https://127.0.0.1:2379"]
    end

    def listen_peer_urls
      self.advertise_peer_urls
    end

    def initial_cluster
      return {}.tap do |rtn|
        self.config.etcd_nodes.each do |_, v|
          rtn[v.member_name] = "https://#{v.member_address}:2380"
        end
      end
    end

    def additional_sans
      sans = []
      [self.member_name, self.member_address].each do |san|
        if self.ipaddr?(san)
          sans << "IP:#{san}"
        else
          sans << "DNS:#{san}"
        end
      end
      return sans
    end

    def etcd_path
      File.join(self.kubelet.addon_path, 'etcd')
    end

    def ca_crt_path
      File.join(self.etcd_path, 'ca.crt')
    end

    def etcd_key_path
      File.join(self.etcd_path, 'etcd.key')
    end

    def etcd_crt_path
      File.join(self.etcd_path, 'etcd.crt')
    end

    def etcd_server_yaml_path
      File.join(self.etcd_path, 'etcd-server.yaml')
    end

    def install_sh_path
      File.join(self.etcd_path, 'install.sh')
    end
  end
end; end
