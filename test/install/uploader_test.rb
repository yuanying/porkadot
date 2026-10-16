require "test_helper"
require "stringio"

class PorkadotInstallUploaderTest < Minitest::Test
  include Porkadot::TestUtils

  class FakeBackend
    attr_reader :calls

    def initialize
      @calls = []
    end

    def execute(*args)
      @calls << [:execute, *args]
    end

    def upload!(local, remote, options = {})
      content = local.respond_to?(:read) ? local.read : File.read(local)
      @calls << [:upload, content, remote, options]
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir
    @config = Porkadot::Config.new(write_tmp_config(@tmpdir))
    @local = File.join(@tmpdir, 'tree')
    @backend = FakeBackend.new
    @uploader = Porkadot::Install::Uploader.new(@config)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_uploads_each_file_to_same_relative_path
    write('install.sh', "echo hi\n", 0644)
    write('addons/etcd/etcd.key', "KEY\n", 0600)

    @uploader.upload_tree(@backend, @local, './kube_temp/kubelet')

    mkdir = @backend.calls.find { |c| c[0] == :execute }
    assert_equal [:execute, :mkdir, '-p', './kube_temp/kubelet', './kube_temp/kubelet/addons/etcd'], mkdir
    uploads = @backend.calls.select { |c| c[0] == :upload }.map { |c| c[1..] }
    assert_equal [
      ["KEY\n", './kube_temp/kubelet/addons/etcd/etcd.key', { mode: 0600 }],
      ["echo hi\n", './kube_temp/kubelet/install.sh', { mode: 0644 }],
    ], uploads
  end

  def test_overlays_multiple_trees_into_same_remote_dir
    write('a/one.txt', "1\n", 0644)
    other = File.join(@tmpdir, 'other')
    FileUtils.mkdir_p(other)
    File.write(File.join(other, 'two.txt'), "2\n")

    @uploader.upload_tree(@backend, @local, './t')
    @uploader.upload_tree(@backend, other, './t')

    remotes = @backend.calls.select { |c| c[0] == :upload }.map { |c| c[2] }
    assert_equal ['./t/a/one.txt', './t/two.txt'], remotes
  end

  private

  def write(rel, content, mode)
    path = File.join(@local, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(mode, path)
  end
end
