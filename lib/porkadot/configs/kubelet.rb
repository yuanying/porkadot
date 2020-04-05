module Porkadot; module Configs
  class Kubelet
    include Porkadot::ConfigUtils
    attr_reader :name
    attr_reader :connection

    def initialize config, name, raw
      @config = config
      @name = name
      @raw = raw || ::Porkadot::Raw.new
      hostname = @raw.hostname || name
      con = { hostname: hostname }
      gcon = config.connection.to_hash
      lcon = @raw.connection ? @raw.connection.to_hash : {}
      @connection = ::Porkadot::Raw.new(con.rmerge(gcon.rmerge(lcon)))
    end

    def apiserver?
      self.raw.labels && self.raw.labels.include?(Porkadot::K8S_MASTER_LABEL)
    end

    def control_plane_endpoint
      (self.raw.kubernetes && self.raw.kubernetes.control_plane_endpoint) || self.config.k8s.control_plane_endpoint
    end

    def labels_string
      return '' unless self.raw.labels
      return self.raw.labels.map{|v| v.compact.join('=')}.join(',')
    end

    def taints_string
      return '' unless self.raw.taints
      return self.raw.taints.map{|v| v.compact.join('=')}.join(',')
    end

    def hostname
      self.raw.hostname || self.name
    end

    def target_path
      File.join(self.config.assets_dir, 'kubelet', name)
    end

    def target_secrets_path
      File.join(self.config.secrets_root_dir, 'kubelet', name)
    end

    def addon_path
      File.join(self.target_path, 'addons')
    end

    def addon_secrets_path
      File.join(self.target_secrets_path, 'addons')
    end

    def ca_crt_path
      File.join(self.target_path, 'ca.crt')
    end

    def bootstrap_key_path
      File.join(self.target_secrets_path, 'bootstrap.key')
    end

    def bootstrap_cert_path
      File.join(self.target_path, 'bootstrap.crt')
    end
  end
end; end

