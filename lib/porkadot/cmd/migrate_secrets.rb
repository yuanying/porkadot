module Porkadot; module Cmd
  # Moves assets/secrets/<group>/... of the legacy layout to
  # assets/<group>/... . Each file is written through AssetStore as a secret,
  # so it is encrypted when local.sops.enabled is true.
  class MigrateSecrets
    attr_reader :config

    def initialize config
      @config = config
    end

    def logger
      config.logger
    end

    def run
      legacy = config.legacy_secrets_dir
      unless File.directory?(legacy)
        return "Nothing to migrate: #{legacy} does not exist."
      end

      files = Dir.glob('**/*', File::FNM_DOTMATCH, base: legacy).sort.select do |rel|
        File.file?(File.join(legacy, rel))
      end
      self.check_conflicts!(legacy, files)

      store = config.asset_store
      files.each do |rel|
        logger.info "--> #{rel}"
        store.copy(File.join(legacy, rel), File.join(config.assets_dir, rel), secret: true)
      end
      FileUtils.rm_rf(legacy)

      "Migrated #{files.size} files from #{legacy} to #{config.assets_dir}. " \
        "Run `porkadot render kubelet`, `render etcd`, `render bootstrap` and `render kubernetes` " \
        "to regenerate scripts for the new layout."
    end

    protected

    def check_conflicts! legacy, files
      store = config.asset_store
      conflicts = files.select do |rel|
        dst = File.join(config.assets_dir, rel)
        File.exist?(dst) && !(File.file?(dst) && store.read(dst).b == store.read(File.join(legacy, rel)).b)
      end
      return if conflicts.empty?
      raise Porkadot::Error, "Cannot migrate secrets: these files already exist with different content " \
        "(nothing was changed): #{conflicts.join(', ')}"
    end
  end
end; end
