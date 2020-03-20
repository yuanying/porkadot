
module Porkadot; module Configs
  class Lb
    include Porkadot::ConfigUtils
    attr_reader :type

    def initialize config
      @config = config
      @type = config.raw.lb.type
      @raw = config.raw.lb.send(config.raw.lb.type.to_sym)
    end

    def target_path
      File.join(self.config.assets_dir, 'kubernetes')
    end

    def manifests_path
      File.join(self.target_path, 'manifests')
    end

    def lb_config
      return self.raw.config
    end

  end
end; end
