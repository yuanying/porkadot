require "test_helper"

class PorkadotMigrateSecretsTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = write_tmp_config(@tmpdir)
    @assets = File.join(@tmpdir, 'assets')
    @legacy = File.join(@assets, 'secrets')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_moves_legacy_secrets_into_regular_tree
    write(File.join(@legacy, 'certs', 'kubernetes', 'ca.key'), "CA KEY\n")
    write(File.join(@legacy, 'kubelet', 'node01', 'bootstrap.key'), "BOOTSTRAP KEY\n")
    write(File.join(@assets, 'kubelet', 'node01', 'bootstrap.crt'), "BOOTSTRAP CRT\n")
    FileUtils.mkdir_p(File.join(@legacy, 'kubelet-default', 'addons'))

    run_cli('migrate-secrets', '--config', @config_path)

    refute File.exist?(@legacy)
    assert_equal "CA KEY\n", File.read(File.join(@assets, 'certs', 'kubernetes', 'ca.key'))
    assert_equal "BOOTSTRAP KEY\n", File.read(File.join(@assets, 'kubelet', 'node01', 'bootstrap.key'))
    assert_equal "BOOTSTRAP CRT\n", File.read(File.join(@assets, 'kubelet', 'node01', 'bootstrap.crt'))
    assert_equal 0600, File.stat(File.join(@assets, 'certs', 'kubernetes', 'ca.key')).mode & 0777
  end

  def test_render_works_after_migration
    write(File.join(@legacy, 'certs', 'kubernetes', 'ca.key'), OpenSSL::PKey::RSA.new(2048).export)

    run_cli('migrate-secrets', '--config', @config_path)
    run_cli('render', 'certs', '--no-ca', '--config', @config_path)

    assert File.file?(File.join(@assets, 'certs', 'kubernetes', 'ca.crt'))
  end

  def test_aborts_without_changes_on_conflicting_file
    write(File.join(@legacy, 'certs', 'kubernetes', 'ca.key'), "LEGACY\n")
    write(File.join(@legacy, 'certs', 'etcd', 'ca.key'), "ETCD\n")
    write(File.join(@assets, 'certs', 'kubernetes', 'ca.key'), "OTHER\n")

    error = assert_raises(Porkadot::Error) do
      run_cli('migrate-secrets', '--config', @config_path)
    end

    assert_match(%r{certs/kubernetes/ca.key}, error.message)
    assert_equal "LEGACY\n", File.read(File.join(@legacy, 'certs', 'kubernetes', 'ca.key'))
    assert_equal "OTHER\n", File.read(File.join(@assets, 'certs', 'kubernetes', 'ca.key'))
    refute File.exist?(File.join(@assets, 'certs', 'etcd', 'ca.key'))
  end

  def test_identical_existing_file_is_not_a_conflict
    write(File.join(@legacy, 'certs', 'kubernetes', 'ca.key'), "SAME\n")
    write(File.join(@assets, 'certs', 'kubernetes', 'ca.key'), "SAME\n")

    run_cli('migrate-secrets', '--config', @config_path)

    refute File.exist?(@legacy)
    assert_equal "SAME\n", File.read(File.join(@assets, 'certs', 'kubernetes', 'ca.key'))
  end

  def test_nothing_to_migrate
    result = nil
    capture_io { result = Porkadot::Cmd::Cli.start(['migrate-secrets', '--config', @config_path]) }

    assert_match(/nothing to migrate/i, result)
  end

  private

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
