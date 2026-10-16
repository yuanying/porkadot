require 'fileutils'

module Porkadot
  # Reads and writes files under assets_dir.
  #
  # Every asset goes through this class so that secrets are handled in one
  # place: they are written with SECRET_MODE, and a file whose content has
  # not changed is left untouched.
  class AssetStore
    SECRET_MODE = 0600

    attr_reader :config

    def initialize config
      @config = config
    end

    def logger
      config.logger
    end

    # Returns the plain content of path.
    def read path
      File.binread(path)
    end

    # Writes content to path and returns true, or returns false when path
    # already holds the same content.
    def write path, content, secret: false
      content = content.to_s.b
      if File.file?(path) && self.read(path).b == content
        File.chmod(SECRET_MODE, path) if secret
        return false
      end

      FileUtils.mkdir_p(File.dirname(path))
      self.write_file(path, content, secret: secret)
      return true
    end

    def copy src, dst, secret: false
      self.write(dst, self.read(src), secret: secret)
    end

    # Mode bits used when the file is uploaded to a node.
    def mode path
      File.stat(path).mode & 0777
    end

    protected

    def write_file path, content, secret: false
      mode = secret ? SECRET_MODE : 0666
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC | File::BINARY, mode) do |f|
        f.write(content)
      end
      File.chmod(SECRET_MODE, path) if secret
    end
  end
end
