require 'fileutils'

module Porkadot
  # Reads and writes files under assets_dir.
  #
  # Every asset goes through this class so that secrets are handled in one
  # place:
  # - secrets are written with SECRET_MODE, and are encrypted with sops when
  #   local.sops.enabled is true;
  # - encrypted files are decrypted in memory when read, whatever the setting;
  # - a file whose plain content has not changed is left untouched, so that
  #   re-rendering does not produce a new ciphertext every time.
  class AssetStore
    SECRET_MODE = 0600

    attr_reader :config
    attr_writer :sops

    def initialize config
      @config = config
    end

    def logger
      config.logger
    end

    def sops
      @sops ||= config.sops
    end

    # Returns the plain content of path.
    def read path
      content = File.binread(path)
      return content unless Porkadot::Sops.encrypted?(content)
      self.sops.decrypt(content, path: path).b
    end

    # Writes content to path and returns true, or returns false when path
    # already holds the same content in the expected form.
    def write path, content, secret: false
      content = content.to_s.b
      encrypt = secret && config.sops_enabled?
      if File.file?(path) && self.up_to_date?(path, content, encrypt)
        File.chmod(SECRET_MODE, path) if secret
        return false
      end

      content = self.sops.encrypt(content, path: path) if encrypt
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

    def up_to_date? path, content, encrypt
      current = File.binread(path)
      encrypted = Porkadot::Sops.encrypted?(current)
      return false if encrypt && !encrypted
      current = self.sops.decrypt(current, path: path).b if encrypted
      current == content
    end

    def write_file path, content, secret: false
      mode = secret ? SECRET_MODE : 0666
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC | File::BINARY, mode) do |f|
        f.write(content)
      end
      File.chmod(SECRET_MODE, path) if secret
    end
  end
end
