require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

class PorkadotRenderCertsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, 'porkadot.yaml')
    config = YAML.load_file(File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml'))
    config['local'] = { 'assets_dir' => File.join(@tmpdir, 'assets') }
    File.write(@config_path, YAML.dump(config))
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_no_ca_keeps_ca_cert_and_refreshes_leaf_certs
    render_certs
    ca_cert = read_cert('kubernetes/ca.crt')
    apiserver_cert = read_cert('kubernetes/apiserver.crt')
    etcd_client_cert = read_cert('etcd/etcd-client.crt')

    render_certs('--no-ca')

    assert_equal ca_cert, read_cert('kubernetes/ca.crt')
    refute_equal apiserver_cert, read_cert('kubernetes/apiserver.crt')
    refute_equal etcd_client_cert, read_cert('etcd/etcd-client.crt')
  end

  def test_default_render_refreshes_ca_cert
    render_certs
    ca_cert = read_cert('kubernetes/ca.crt')

    render_certs

    refute_equal ca_cert, read_cert('kubernetes/ca.crt')
  end

  private

  def render_certs(*args)
    capture_io do
      Porkadot::Cmd::Cli.start(['render', 'certs'] + args + ['--config', @config_path])
    end
  end

  def read_cert(path)
    File.read(File.join(@tmpdir, 'assets', 'secrets', 'certs', path))
  end
end
