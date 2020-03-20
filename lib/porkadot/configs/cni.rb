
module Porkadot; module Configs
  class Cni
    include Porkadot::ConfigUtils
    attr_reader :type

    def initialize config
      @config = config
      @type = config.raw.cni.type
      @raw = config.raw.cni.send(config.raw.cni.type.to_sym)
    end

    def target_path
      File.join(self.config.assets_dir, 'kubernetes')
    end

    def manifests_path
      File.join(self.target_path, 'manifests')
    end

  end
end; end
