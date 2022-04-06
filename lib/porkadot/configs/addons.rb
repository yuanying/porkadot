
module Porkadot; module Configs
  class Addons
    include Porkadot::ConfigUtils

    def initialize config
      @config = config
      @raw = config.raw.addons
    end

    def target_path
      File.join(self.config.assets_dir, 'kubernetes', 'manifests', 'addons')
    end

    def target_secrets_path
      File.join(self.config.secrets_root_dir, 'kubernetes', 'manifests', 'addons')
    end

  end
end; end

