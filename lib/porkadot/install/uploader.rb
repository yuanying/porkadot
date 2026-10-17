require 'stringio'

module Porkadot; module Install
  # Uploads a local assets tree file by file, so that several trees can be
  # overlaid into one remote directory. Contents are read through AssetStore
  # and sent from memory, and each file keeps its local mode bits.
  class Uploader
    attr_reader :config

    def initialize config
      @config = config
    end

    # backend is the SSHKit backend (self inside an `on` block).
    def upload_tree backend, local_dir, remote_dir
      files = Dir.glob('**/*', File::FNM_DOTMATCH, base: local_dir).sort.select do |rel|
        File.file?(File.join(local_dir, rel))
      end
      dirs = files.map { |rel| File.dirname(rel) }.uniq.reject { |d| d == '.' }
      backend.execute(:mkdir, '-p', remote_dir, *dirs.map { |d| File.join(remote_dir, d) })

      files.each do |rel|
        self.upload_file(backend, File.join(local_dir, rel), File.join(remote_dir, rel))
      end
    end

    def upload_file backend, local, remote
      store = config.asset_store
      backend.upload!(StringIO.new(store.read(local)), remote, mode: store.mode(local))
    end
  end
end; end
