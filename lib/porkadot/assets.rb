module Porkadot::Assets

  def render_erb file, opts={}
    file = file.to_s
    opts[:config] = self.config
    opts[:global_config] = self.global_config
    logger.info "----> #{file}"
    open(File.join(self.class::TEMPLATE_DIR, "#{file}.erb")) do |io|
      open(config.asset_path(file), 'w') do |out|
        out.write ERB.new(io.read, trim_mode: '-').result_with_hash(opts)
      end
    end
  end

end
