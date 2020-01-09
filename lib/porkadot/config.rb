require 'yaml'
require 'hashie'

module Porkadot
  class Config
    attr_reader :raw

    def initialize path
      open(File.expand_path(path)) do |io|
        @raw = ::Hashie::Mash.new(YAML.load(io))
      end
    end

    def assets_dir
      File.expand_path(raw.assets_dir)
    end
  end
end
