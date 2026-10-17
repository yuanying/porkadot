require "test_helper"
require "sops_helper"
require "stringio"

# Runs render, migrate-secrets and upload with the real sops binary.
class PorkadotSopsIntegrationTest < Minitest::Test
  include Porkadot::TestUtils
  include Porkadot::SopsTestUtils

  class RecordingBackend
    attr_reader :files

    def initialize
      @files = {}
    end

    def execute(*); end

    def upload!(local, remote, options = {})
      @files[remote] = local.read
    end
  end

  SECRETS = %w(
    certs/kubernetes/ca.key
    certs/kubernetes/ca.crt
    certs/etcd/etcd-client.key
    kubernetes/kubeconfig.yaml
    kubernetes/install.secrets.sh
    kubernetes/manifests/kube-apiserver.secrets.yaml
    kubernetes/manifests/kube-controller-manager.secrets.yaml
    kubelet/node01/bootstrap.key
    kubelet/node01/addons/etcd/etcd.key
    kubelet/node01/addons/etcd/etcd.crt
    bootstrap/kubelet/bootstrap.key
    bootstrap/bootstrap/secrets/kubernetes/ca.key
  )

  PLAIN = %w(
    kubernetes/install.sh
    kubernetes/manifests/kube-apiserver.yaml
    kubelet/node01/bootstrap.crt
    kubelet/node01/config.yaml
    kubelet-default/ca.crt
  )

  def setup
    @tmpdir = Dir.mktmpdir
    setup_sops(@tmpdir)
    @plain_dir = File.join(@tmpdir, 'plain')
    FileUtils.mkdir_p(@plain_dir)
    @plain_config = write_tmp_config(@plain_dir)
    @sops_config = write_tmp_config(@tmpdir, local_overrides: { 'sops' => { 'enabled' => true } })
    @assets = File.join(@tmpdir, 'assets')
  end

  def teardown
    teardown_sops
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_render_encrypts_secrets_only
    render_all(@sops_config)

    SECRETS.each do |path|
      assert sops_encrypted_file?(File.join(@assets, path)), "#{path} should be encrypted"
    end
    PLAIN.each do |path|
      refute sops_encrypted_file?(File.join(@assets, path)), "#{path} should be plain"
    end
  end

  def test_rerender_keeps_encrypted_secrets_unchanged
    render_all(@sops_config)
    files = %w(
      kubernetes/kubeconfig.yaml
      kubernetes/install.secrets.sh
      kubernetes/manifests/kube-apiserver.secrets.yaml
      bootstrap/bootstrap/secrets/kubernetes/ca.key
      bootstrap/bootstrap/secrets/kubernetes/apiserver.crt
      bootstrap/kubelet/bootstrap.key
      kubelet/node01/bootstrap.key
      kubelet/node01/addons/etcd/etcd.key
    )
    before = files.map { |f| File.binread(File.join(@assets, f)) }

    %w(kubelet etcd bootstrap kubernetes).each do |group|
      run_cli('render', group, '--config', @sops_config)
    end

    assert_equal before, files.map { |f| File.binread(File.join(@assets, f)) }
  end

  def test_migrated_and_uploaded_assets_match_plain_render
    render_all(@plain_config)
    plain_assets = File.join(@plain_dir, 'assets')
    FileUtils.mkdir_p(File.join(@assets, 'secrets'))
    FileUtils.cp_r(File.join(plain_assets, 'certs'), File.join(@assets, 'secrets', 'certs'))

    run_cli('migrate-secrets', '--config', @sops_config)
    assert sops_encrypted_file?(File.join(@assets, 'certs', 'kubernetes', 'ca.key'))
    %w(bootstrap kubernetes).each do |group|
      run_cli('render', group, '--config', @sops_config)
    end

    config = Porkadot::Config.new(@sops_config)
    %w(kubernetes bootstrap/bootstrap).each do |tree|
      backend = RecordingBackend.new
      Porkadot::Install::Uploader.new(config).upload_tree(backend, File.join(@assets, tree), '/remote')
      plain = Dir.glob('**/*', base: File.join(plain_assets, tree)).select { |f| File.file?(File.join(plain_assets, tree, f)) }

      assert_equal plain.sort, backend.files.keys.map { |k| k.delete_prefix('/remote/') }.sort
      plain.each do |rel|
        assert_equal File.binread(File.join(plain_assets, tree, rel)), backend.files["/remote/#{rel}"].b, "#{tree}/#{rel}"
      end
    end
  end

  private

  def render_all config_path
    %w(certs kubelet etcd bootstrap kubernetes).each do |group|
      run_cli('render', group, '--config', config_path)
    end
  end
end
