class Porkadot::SubCommandBase < Thor
  def self.banner(command, namespace = nil, subcommand = false)
    "#{basename} #{subcommand_prefix} #{command.usage}"
  end

  def self.subcommand_prefix
    self.name.gsub(%r{.*::}, '').gsub(%r{^[A-Z]}) { |match| match[0].downcase }.gsub(%r{[A-Z]}) { |match| "-#{match[0].downcase}" }
  end
end

module Porkadot::Utils
  # Loads porkadot.yaml. Commands that read or write assets refuse to run
  # while the legacy assets/secrets layout is present; see
  # assets_layout_check?.
  def config
    config = self.loaded_config
    unless defined?(@assets_layout_checked)
      config.ensure_current_assets_layout! if self.assets_layout_check?
      @assets_layout_checked = true
    end
    config
  end

  def loaded_config
    unless defined?(@config)
      opts = options.dup
      opts = opts.merge(parent_options) if parent_options
      @config = Porkadot::Config.new(opts[:config])
      @config.validate!
    end
    @config
  end

  def assets_layout_check?
    true
  end

  def logger
    self.loaded_config.logger
  end
end
