class Porkadot::SubCommandBase < Thor
  def self.banner(command, namespace = nil, subcommand = false)
    "#{basename} #{subcommand_prefix} #{command.usage}"
  end

  def self.subcommand_prefix
    self.name.gsub(%r{.*::}, '').gsub(%r{^[A-Z]}) { |match| match[0].downcase }.gsub(%r{[A-Z]}) { |match| "-#{match[0].downcase}" }
  end
end

module Porkadot::Utils
  def config
    unless defined?(@config)
      opts = options.dup
      opts = opts.merge(parent_options) if parent_options
      @config = Porkadot::Config.new(options[:config])
    end
    @config
  end
end
