require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

class PorkadotRenderAddonsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_cnidaria_renders_manifests_and_crd_without_flannel
    render_addons(['cnidaria', 'coredns'])

    assert File.file?(addon_path('cnidaria/cnidaria.yaml'))
    assert File.file?(addon_path('cnidaria/kustomization.yaml'))
    assert File.file?(crd_path('cnidaria/crds.yaml'))
    refute File.exist?(addon_path('flannel'))

    kustomization = YAML.load_file(addon_path('kustomization.yaml'))
    assert_includes kustomization['resources'], 'cnidaria'
    refute_includes kustomization['resources'], 'flannel'

    crd = YAML.load_file(crd_path('cnidaria/crds.yaml'))
    assert_equal 'nodenetworkpolicies.cnidaria.unstable.cloud', crd['metadata']['name']
  end

  def test_cnidaria_daemonset_uses_default_image_and_network_name
    render_addons(['cnidaria'])

    ds = cnidaria_daemonset
    images = pod_spec(ds).values_at('initContainers', 'containers').flatten.map { |c| c['image'] }
    assert_equal ['ghcr.io/yuanying/cnidaria-cni:v0.1.0'] * 2, images

    container = pod_spec(ds)['containers'].first
    assert_includes container['args'], '--network-name=cnidaria'
    assert_equal({ 'cpu' => '50m', 'memory' => '64Mi' }, container['resources']['requests'])
    assert_equal({ 'memory' => '256Mi' }, container['resources']['limits'])
  end

  def test_cnidaria_settings_can_be_overridden
    render_addons(['cnidaria'], 'cnidaria' => {
      'image_repository' => 'registry.example.com/cnidaria-cni',
      'image_tag' => 'v9.9.9',
      'network_name' => 'cbr0',
      'resources' => { 'requests' => { 'cpu' => '10m' } },
    })

    ds = cnidaria_daemonset
    images = pod_spec(ds).values_at('initContainers', 'containers').flatten.map { |c| c['image'] }
    assert_equal ['registry.example.com/cnidaria-cni:v9.9.9'] * 2, images

    container = pod_spec(ds)['containers'].first
    assert_includes container['args'], '--network-name=cbr0'
    assert_equal '10m', container['resources']['requests']['cpu']
  end

  def test_cnidaria_objects_live_in_kube_system
    render_addons(['cnidaria'])

    docs = YAML.load_stream(File.read(addon_path('cnidaria/cnidaria.yaml'))).compact
    kinds = docs.map { |d| d['kind'] }
    assert_equal %w[ClusterRole ClusterRoleBinding DaemonSet ServiceAccount], kinds.sort

    namespaced = docs.select { |d| %w[ServiceAccount DaemonSet].include?(d['kind']) }
    assert namespaced.all? { |d| d['metadata']['namespace'] == 'kube-system' }
  end

  private

  def render_addons(enabled, extra = {})
    config = YAML.load_file(File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml'))
    config['local'] = { 'assets_dir' => File.join(@tmpdir, 'assets') }
    config['addons'] = { 'enabled' => enabled }.merge(extra)
    config_path = File.join(@tmpdir, 'porkadot.yaml')
    File.write(config_path, YAML.dump(config))

    capture_io do
      Porkadot::Assets::Addons.new(Porkadot::Config.new(config_path)).render
    end
  end

  def addon_path(file)
    File.join(@tmpdir, 'assets', 'kubernetes', 'manifests', 'addons', file)
  end

  def crd_path(file)
    File.join(@tmpdir, 'assets', 'kubernetes', 'manifests', 'crds', file)
  end

  def cnidaria_daemonset
    YAML.load_stream(File.read(addon_path('cnidaria/cnidaria.yaml')))
      .compact.find { |d| d['kind'] == 'DaemonSet' }
  end

  def pod_spec(ds)
    ds['spec']['template']['spec']
  end
end
