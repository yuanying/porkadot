require "test_helper"

class PorkadotRenderLayoutTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = write_tmp_config(@tmpdir)
    @assets = File.join(@tmpdir, 'assets')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_render_writes_secrets_into_regular_tree
    render_all

    refute File.exist?(File.join(@assets, 'secrets')), 'assets/secrets must not be created'
    %w(
      certs/kubernetes/ca.key
      certs/etcd/ca.key
      kubernetes/kubeconfig.yaml
      kubernetes/install.secrets.sh
      kubernetes/manifests/kube-apiserver.secrets.yaml
      kubernetes/manifests/kube-controller-manager.secrets.yaml
      kubelet/node01/bootstrap.key
      kubelet/node01/addons/etcd/etcd.key
      kubelet/node01/addons/etcd/etcd.crt
      kubelet/node01/addons/etcd/ca.crt
      bootstrap/kubelet/bootstrap.key
      bootstrap/bootstrap/secrets/kubernetes/ca.key
      bootstrap/bootstrap/secrets/etcd/etcd-client.key
    ).each do |path|
      assert File.file?(File.join(@assets, path)), "#{path} should be rendered"
    end
  end

  def test_secret_files_are_only_readable_by_owner
    render_all

    %w(
      certs/kubernetes/ca.key
      kubernetes/kubeconfig.yaml
      kubelet/node01/bootstrap.key
      bootstrap/bootstrap/secrets/kubernetes/ca.key
    ).each do |path|
      assert_equal 0600, File.stat(File.join(@assets, path)).mode & 0777, path
    end
  end

  def test_install_secrets_applies_only_secret_manifests
    render_all
    script = File.read(File.join(@assets, 'kubernetes', 'install.secrets.sh'))

    assert_includes script, '${ROOT}/manifests/kube-apiserver.secrets.yaml'
    assert_includes script, '${ROOT}/manifests/kube-controller-manager.secrets.yaml'
    refute_match %r{-R -f \$\{ROOT\}/manifests\s*$}, script
  end

  def test_render_refuses_legacy_secrets_layout
    FileUtils.mkdir_p(File.join(@assets, 'secrets', 'certs'))

    %w(certs kubelet etcd bootstrap kubernetes).each do |group|
      error = assert_raises(Porkadot::Error) do
        run_cli('render', group, '--config', @config_path)
      end
      assert_match(/migrate-secrets/, error.message)
    end
    refute File.exist?(File.join(@assets, 'certs')), 'nothing should be rendered'
  end

  private

  def render_all
    %w(certs kubelet etcd bootstrap kubernetes).each do |group|
      run_cli('render', group, '--config', @config_path)
    end
  end
end
