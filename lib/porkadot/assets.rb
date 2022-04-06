module Porkadot::Assets
  class ErbUtils
    def indent(text, space=2)
      space = space.times.map{' '}.join('')
      text.lines.map{|line| "#{space}#{line}"}.join('')
    end

    def to_yaml(obj, space=0)
      h = Hashie::Mash.new({obj: obj})
      h = h.to_hash
      if h['obj'].size == 0
        return ''
      end
      return self.indent(h['obj'].to_yaml(canonical: false, header: false).gsub(/---\n/, ''), space)
    end
  end

  def render_erb file, opts={}
    file = file.to_s
    opts[:config] = self.config
    opts[:global_config] = self.global_config
    opts[:certs] = Porkadot::Assets::Certs.new(self.global_config)
    opts[:u] = ErbUtils.new

    logger.info "----> #{file}"
    asset = config.asset_path(file)
    asset_dir = File.dirname(asset)
    FileUtils.mkdir_p(asset_dir) unless File.directory?(asset_dir)
    open(File.join(self.class::TEMPLATE_DIR, "#{file}.erb")) do |io|
      open(asset, 'w') do |out|
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
    secret = config.secrets_path(file)
    secret_dir = File.dirname(secret)
    FileUtils.mkdir_p(secret_dir) unless File.directory?(secret_dir)
    open(File.join(self.class::TEMPLATE_DIR, "#{file}.erb")) do |io|
      open(secret, 'w') do |out|
        out.write ERB.new(io.read, trim_mode: '-').result_with_hash(opts)
      end
    end
  end

end
