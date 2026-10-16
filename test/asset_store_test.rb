require "test_helper"
require "json"

class PorkadotAssetStoreTest < Minitest::Test
  include Porkadot::TestUtils

  # Stands in for Porkadot::Sops: "encrypts" by wrapping content in a sops
  # binary-format document.
  class FakeSops
    attr_reader :encrypt_calls

    def initialize
      @encrypt_calls = 0
    end

    def encrypt content, path:
      @encrypt_calls += 1
      JSON.dump('data' => content.unpack1('H*'), 'sops' => { 'version' => 'fake' })
    end

    def decrypt content, path:
      [JSON.parse(content)['data']].pack('H*')
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir
    @path = File.join(@tmpdir, 'assets', 'certs', 'ca.key')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def store sops_enabled: true
    config = Porkadot::Config.new(write_tmp_config(@tmpdir, local_overrides: { 'sops' => { 'enabled' => sops_enabled } }))
    @sops = FakeSops.new
    store = config.asset_store
    store.sops = @sops
    store
  end

  def test_plain_write_and_read
    s = store(sops_enabled: false)

    assert s.write(@path, "KEY\n", secret: true)

    assert_equal "KEY\n", File.read(@path)
    assert_equal "KEY\n", s.read(@path)
    assert_equal 0600, File.stat(@path).mode & 0777
    assert_equal 0, @sops.encrypt_calls
  end

  def test_secret_is_encrypted_when_sops_enabled
    s = store

    s.write(@path, "KEY\n", secret: true)

    assert Porkadot::Sops.encrypted?(File.read(@path))
    assert_equal "KEY\n", s.read(@path)
    assert_equal 0600, File.stat(@path).mode & 0777
  end

  def test_non_secret_is_not_encrypted
    s = store

    s.write(@path, "CERT\n")

    assert_equal "CERT\n", File.read(@path)
  end

  def test_same_content_is_not_rewritten
    s = store
    s.write(@path, "KEY\n", secret: true)
    encrypted = File.read(@path)

    refute s.write(@path, "KEY\n", secret: true)

    assert_equal encrypted, File.read(@path)
    assert_equal 1, @sops.encrypt_calls
  end

  def test_changed_content_is_reencrypted
    s = store
    s.write(@path, "KEY\n", secret: true)

    assert s.write(@path, "NEW KEY\n", secret: true)

    assert_equal "NEW KEY\n", s.read(@path)
    assert_equal 2, @sops.encrypt_calls
  end

  def test_plain_secret_is_encrypted_even_if_content_is_same
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "KEY\n")
    s = store

    assert s.write(@path, "KEY\n", secret: true)

    assert Porkadot::Sops.encrypted?(File.read(@path))
  end

  def test_copy_reads_plain_content
    s = store
    s.write(@path, "KEY\n", secret: true)
    dst = File.join(@tmpdir, 'assets', 'bootstrap', 'ca.key')

    s.copy(@path, dst, secret: true)

    assert_equal "KEY\n", s.read(dst)
  end
end
