require "test_helper"

class PorkadotRenderBootstrapTest < Minitest::Test
  include Porkadot::TestUtils

  # Certificates and keys the bootstrap control plane reads from its secrets.
  BOOTSTRAP_SECRETS = %w(
    etcd/ca.crt
    etcd/ca.key
    etcd/etcd-client.crt
    etcd/etcd-client.key
    kubernetes/ca.crt
    kubernetes/ca.key
    kubernetes/apiserver.crt
    kubernetes/apiserver.key
    kubernetes/kubelet-client.crt
    kubernetes/kubelet-client.key
    kubernetes/admin.crt
    kubernetes/admin.key
    kubernetes/sa.key
    kubernetes/sa.pub
    kubernetes/front-proxy-ca.crt
    kubernetes/front-proxy-ca.key
    kubernetes/front-proxy-client.crt
    kubernetes/front-proxy-client.key
  )

  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = write_tmp_config(@tmpdir)
    @assets = File.join(@tmpdir, 'assets')
    @certs = File.join(@assets, 'certs')
    @secrets = File.join(@assets, 'bootstrap', 'bootstrap', 'secrets')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_render_bootstrap_alone_provides_every_secret
    run_cli('render', 'bootstrap', '--config', @config_path)

    BOOTSTRAP_SECRETS.each do |path|
      assert File.file?(File.join(@secrets, path)), "#{path} should be in the bootstrap secrets"
      assert_equal File.binread(File.join(@certs, path)), File.binread(File.join(@secrets, path)), path
    end
  end

  def test_render_bootstrap_copies_what_render_certs_creates
    run_cli('render', 'certs', '--config', @config_path)
    run_cli('render', 'bootstrap', '--config', @config_path)

    assert_equal files_in(@certs), files_in(@secrets)
  end

  def test_render_bootstrap_keeps_existing_certs
    run_cli('render', 'certs', '--config', @config_path)
    before = snapshot(@certs)

    run_cli('render', 'bootstrap', '--config', @config_path)

    assert_equal before, snapshot(@certs)
    assert_equal before, snapshot(@secrets)
  end

  private

  def files_in(dir)
    Dir.glob('**/*', base: dir).select { |rel| File.file?(File.join(dir, rel)) }.sort
  end

  def snapshot(dir)
    files_in(dir).to_h { |rel| [rel, File.binread(File.join(dir, rel))] }
  end
end
