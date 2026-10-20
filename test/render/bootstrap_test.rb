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

  # Since 1.34 the kubelet rejects static Pods that refer to API objects
  # (PreventStaticPodAPIReferences). The bootstrap Pods and etcd are static Pods.
  def test_static_pods_refer_to_no_api_objects
    run_cli('render', 'bootstrap', '--config', @config_path)
    run_cli('render', 'etcd', '--config', @config_path)

    manifests = Dir.glob(File.join(@assets, 'bootstrap', 'manifests', '*.yaml')) +
      Dir.glob(File.join(@assets, 'kubelet', '*', 'addons', 'etcd', 'etcd-server.yaml'))
    assert_includes manifests.map { |m| File.basename(m) }, 'kube-proxy.bootstrap.yaml'
    assert_includes manifests.map { |m| File.basename(m) }, 'etcd-server.yaml'

    manifests.each do |manifest|
      YAML.load_stream(File.read(manifest)).compact.each do |pod|
        assert_equal 'Pod', pod['kind'], manifest
        assert_no_api_references pod['spec'], manifest
      end
    end
  end

  private

  def assert_no_api_references(spec, manifest)
    assert_nil spec['serviceAccountName'], manifest
    assert_nil spec['serviceAccount'], manifest
    assert_nil spec['imagePullSecrets'], manifest
    assert_nil spec['resourceClaims'], manifest
    (spec['volumes'] || []).each do |volume|
      assert_equal [], volume.keys - %w(name hostPath emptyDir), "#{manifest}: #{volume['name']}"
    end
    (spec['containers'] + (spec['initContainers'] || [])).each do |container|
      assert_nil container['envFrom'], manifest
      (container['env'] || []).each do |env|
        refs = (env['valueFrom'] || {}).keys - %w(fieldRef resourceFieldRef)
        assert_empty refs, "#{manifest}: #{env['name']}"
      end
    end
  end

  def files_in(dir)
    Dir.glob('**/*', base: dir).select { |rel| File.file?(File.join(dir, rel)) }.sort
  end

  def snapshot(dir)
    files_in(dir).to_h { |rel| [rel, File.binread(File.join(dir, rel))] }
  end
end
