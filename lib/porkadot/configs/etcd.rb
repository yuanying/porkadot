
module Porkadot; module Configs
  class Etcd
    include Porkadot::ConfigUtils
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

    def etcd_path
      File.join(self.kubelet.kubelet_path, 'etcd')
    end
  end
end; end
