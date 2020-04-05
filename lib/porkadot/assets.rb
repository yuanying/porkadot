module Porkadot::Assets
  class ErbUtils
    def indent(text, space=2)
      space = space.times.map{' '}.join('')
      text.lines.map{|line| "#{space}#{line}"}.join('')
    end
  end

  def render_erb file, opts={}
    file = file.to_s
    opts[:config] = self.config
    opts[:global_config] = self.global_config
    opts[:certs] = Porkadot::Assets::Certs.new(self.global_config)
    opts[:u] = ErbUtils.new

    logger.info "----> #{file}"
    open(File.join(self.class::TEMPLATE_DIR, "#{file}.erb")) do |io|
      open(config.asset_path(file), 'w') do |out|
        out.write ERB.new(io.read, trim_mode: '-').result_with_hash(opts)
      end
    end
  end

  def render_secrets_erb file, opts={}
    file = file.to_s
    opts[:config] = self.config
    opts[:global_config] = self.global_config
    opts[:certs] = Porkadot::Assets::Certs.new(self.global_config)
    opts[:u] = ErbUtils.new

    logger.info "----> #{file}"
    open(File.join(self.class::TEMPLATE_DIR, "#{file}.erb")) do |io|
      open(config.secrets_path(file), 'w') do |out|
        out.write ERB.new(io.read, trim_mode: '-').result_with_hash(opts)
      end
    end
  end

end
