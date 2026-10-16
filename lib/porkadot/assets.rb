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

  # Renders TEMPLATE_DIR/<file>.erb to the asset path of file.
  # Pass secret: true for outputs that contain credentials.
  def render_erb file, secret: false, **opts
    file = file.to_s
    opts[:config] = self.config
    opts[:global_config] = self.global_config
    opts[:certs] = Porkadot::Assets::Certs.new(self.global_config)
    opts[:u] = ErbUtils.new

    logger.info "----> #{file}"
    asset = config.asset_path(file)
    if opts[:force] != nil && File.file?(asset)
      logger.debug "------> Already exists: skipping #{file}"
      return
    end
    content = open(File.join(self.class::TEMPLATE_DIR, "#{file}.erb")) do |io|
      ERB.new(io.read, trim_mode: '-').result_with_hash(opts)
    end
    self.global_config.asset_store.write(asset, content, secret: secret)
  end

end
