require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

class PorkadotRenderAddonsTest < Minitest::Test
  include Porkadot::TestUtils

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
    images = pod_spec(ds)['containers'].map { |c| c['image'] }
    tag = default_config.dig('addons', 'cnidaria', 'image_tag')
    assert_equal ["ghcr.io/yuanying/cnidaria-cni:#{tag}"], images

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
    images = pod_spec(ds)['containers'].map { |c| c['image'] }
    assert_equal ['registry.example.com/cnidaria-cni:v9.9.9'], images

    container = pod_spec(ds)['containers'].first
    assert_includes container['args'], '--network-name=cbr0'
    assert_equal '10m', container['resources']['requests']['cpu']
  end

  # The reference CNI plugins are put in /opt/cni/bin by install kubelet, so the
  # DaemonSet must not copy its own and overwrite them.
  def test_cnidaria_daemonset_leaves_cni_bin_dir_alone
    render_addons(['cnidaria'])

    spec = pod_spec(cnidaria_daemonset)
    assert_nil spec['initContainers']
    host_paths = spec['volumes'].map { |v| v.dig('hostPath', 'path') }.compact
    refute_includes host_paths, '/opt/cni/bin'
  end

  def test_cnidaria_daemonset_tolerates_every_taint
    render_addons(['cnidaria'])

    assert_equal [{ 'operator' => 'Exists' }], pod_spec(cnidaria_daemonset)['tolerations']
  end

  def test_cnidaria_objects_live_in_kube_system
    render_addons(['cnidaria'])

    docs = YAML.load_stream(File.read(addon_path('cnidaria/cnidaria.yaml'))).compact
    kinds = docs.map { |d| d['kind'] }
    assert_equal %w[ClusterRole ClusterRoleBinding DaemonSet ServiceAccount], kinds.sort

    namespaced = docs.select { |d| %w[ServiceAccount DaemonSet].include?(d['kind']) }
    assert namespaced.all? { |d| d['metadata']['namespace'] == 'kube-system' }
  end

  def test_coredns_uses_default_image
    render_addons(['coredns'])

    deploy = YAML.load_stream(File.read(addon_path('coredns/coredns.yaml')))
      .compact.find { |d| d['kind'] == 'Deployment' && d['metadata']['name'] == 'coredns' }
    images = pod_spec(deploy)['containers'].map { |c| c['image'] }
    image = renovate_tracked_image('kubernetes/manifests/addons/coredns/coredns.yaml.erb',
                                   'registry.k8s.io/coredns/coredns')
    assert_match %r{\Aregistry\.k8s\.io/coredns/coredns:v\d+\.\d+\.\d+\z}, image
    assert_equal [image], images
  end

  # Same as kubeadm's Corefile since 1.32: answers for the cluster domain
  # are not cached, so that they never lag behind the kubernetes plugin.
  def test_coredns_cache_skips_cluster_domain
    render_addons(['coredns'])

    config_map = YAML.load_stream(File.read(addon_path('coredns/coredns.yaml')))
      .compact.find { |d| d['kind'] == 'ConfigMap' && d['metadata']['name'] == 'coredns' }
    corefile = config_map['data']['Corefile']
    assert_match(/^ {4}cache 30 \{\n {8}disable success cluster\.local\n {8}disable denial cluster\.local\n {4}\}\n/, corefile)
  end

  # The seccomp annotation is no longer honoured; only the field is.
  def test_coredns_uses_runtime_default_seccomp_profile
    render_addons(['coredns'])

    deploy = coredns_deployment
    assert_nil deploy.dig('spec', 'template', 'metadata', 'annotations')
    assert_equal({ 'type' => 'RuntimeDefault' }, pod_spec(deploy)['securityContext']['seccompProfile'])
  end

  # Port 53 needs only NET_BIND_SERVICE, as in kubeadm's and the addon's manifests.
  def test_coredns_container_keeps_upstream_security_context
    render_addons(['coredns'])

    assert_equal({
      'allowPrivilegeEscalation' => false,
      'capabilities' => { 'add' => ['NET_BIND_SERVICE'], 'drop' => ['ALL'] },
      'readOnlyRootFilesystem' => true,
    }, pod_spec(coredns_deployment)['containers'].first['securityContext'])
  end

  # The multi-arch image, so that the Pod may run on the arm64 control plane too.
  def test_dns_autoscaler_uses_multi_arch_image
    render_addons(['coredns'])

    images = pod_spec(dns_autoscaler_deployment)['containers'].map { |c| c['image'] }
    image = renovate_tracked_image('kubernetes/manifests/addons/coredns/dns-horizontal-autoscaler.yaml.erb',
                                   'registry.k8s.io/cpa/cluster-proportional-autoscaler')
    assert_match %r{\Aregistry\.k8s\.io/cpa/cluster-proportional-autoscaler:v\d+\.\d+\.\d+\z}, image
    assert_equal [image], images
  end

  def test_dns_autoscaler_scales_coredns_linearly
    render_addons(['coredns'])

    command = pod_spec(dns_autoscaler_deployment)['containers'].first['command']
    assert_equal [
      '/cluster-proportional-autoscaler',
      '--namespace=kube-system',
      '--configmap=kube-dns-autoscaler',
      '--target=Deployment/coredns',
      '--default-params={"linear":{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}}',
      '--logtostderr=true',
      '--v=2',
    ], command
  end

  # The seccomp annotation is no longer honoured; only the field is.
  def test_dns_autoscaler_uses_runtime_default_seccomp_profile
    render_addons(['coredns'])

    deploy = dns_autoscaler_deployment
    assert_nil deploy.dig('spec', 'template', 'metadata', 'annotations')
    assert_equal({ 'type' => 'RuntimeDefault' }, pod_spec(deploy)['securityContext']['seccompProfile'])
  end

  def test_metallb_uses_v0_16_1_images
    render_addons(['metallb'])

    images = metallb_docs.select { |d| %w[Deployment DaemonSet].include?(d['kind']) }
      .flat_map { |d| pod_spec(d)['containers'].map { |c| c['image'] } }
    assert_equal %w[quay.io/metallb/controller:v0.16.1 quay.io/metallb/speaker:v0.16.1], images.sort
  end

  # The template and the CRDs are rendered from hack/metallb by
  # hack/update-metallb.sh. A ref changed without rendering again would name
  # a release that porkadot does not install.
  def test_metallb_hack_kustomizations_name_the_rendered_release
    refs = %w[kustomization.yaml crds/kustomization.yaml].flat_map do |f|
      YAML.load_file(File.join(ROOT, 'hack', 'metallb', f))['resources']
        .grep(%r{\Ahttps://github\.com/metallb/metallb/}).map { |r| r[/\?ref=(\S+)\z/, 1] }
    end
    assert_equal ['v0.16.1'], refs.uniq
  end

  # The custom resources a cluster already has must stay readable, and they
  # must already be stored in the storage version, so that status.storedVersions
  # does not grow.
  def test_metallb_crds_keep_served_and_storage_versions
    render_addons(['metallb'])

    crds = YAML.load_stream(File.read(crd_path('metallb/crds.yaml'))).compact
      .to_h { |d| [d['metadata']['name'], d['spec']['versions']] }
    storage = crds.transform_values { |vs| vs.find { |v| v['storage'] }['name'] }
    served = crds.transform_values { |vs| vs.select { |v| v['served'] }.map { |v| v['name'] } }

    assert_equal 'v1beta1', storage['ipaddresspools.metallb.io']
    assert_equal 'v1beta1', storage['l2advertisements.metallb.io']
    assert_equal 'v1beta2', storage['bgppeers.metallb.io']
    assert_equal %w[v1beta1 v1beta2], served['bgppeers.metallb.io']
    refute crds.key?('addresspools.metallb.io')
  end

  # porkadot keeps its own list of interfaces not to announce on. The
  # upstream list anchors each pattern, and would announce on the node's
  # porka-dummy01 that holds the cluster DNS address.
  def test_metallb_does_not_announce_on_porka_dummy
    render_addons(['metallb'])

    config_map = metallb_docs.find { |d| d['kind'] == 'ConfigMap' && d['metadata']['name'] == 'metallb-excludel2' }
    patterns = YAML.safe_load(config_map['data']['excludel2.yaml'])['announcedInterfacesToExclude']
    assert patterns.any? { |p| Regexp.new(p).match?('porka-dummy01') }
    refute patterns.any? { |p| Regexp.new(p).match?('eth0') }
  end

  def test_kubelet_serving_cert_approver_uses_pinned_image
    render_addons(['kubelet-serving-cert-approver'])

    container = pod_spec(approver_deployment)['containers'].first
    tag = default_config.dig('addons', 'kubelet-serving-cert-approver', 'image_tag')
    assert_match(/\A\d+\.\d+\.\d+\z/, tag)
    assert_equal "ghcr.io/alex1989hu/kubelet-serving-cert-approver:#{tag}", container['image']
    assert_equal 'IfNotPresent', container['imagePullPolicy']
  end

  def test_kubelet_serving_cert_approver_image_can_be_overridden
    render_addons(['kubelet-serving-cert-approver'], 'kubelet-serving-cert-approver' => {
      'image_repository' => 'registry.example.com/kubelet-serving-cert-approver',
      'image_tag' => '9.9.9',
    })

    container = pod_spec(approver_deployment)['containers'].first
    assert_equal 'registry.example.com/kubelet-serving-cert-approver:9.9.9', container['image']
  end

  def test_kubelet_serving_cert_approver_matches_upstream_v0_12_1
    render_addons(['kubelet-serving-cert-approver'])

    spec = pod_spec(approver_deployment)
    startup = spec['containers'].first['startupProbe']
    assert_equal({ 'path' => '/healthz', 'port' => 'health' }, startup['httpGet'])
    assert_equal 30, startup['failureThreshold']
    assert_equal 10, startup['periodSeconds']

    taints = spec['tolerations'].map { |t| t['key'] }
    assert_includes taints, 'node.cloudprovider.kubernetes.io/uninitialized'
    assert_includes taints, 'node-role.kubernetes.io/master'
    assert_includes taints, 'node-role.kubernetes.io/control-plane'
  end

  def test_default_addons_do_not_render_storage_version_migrator
    config = YAML.load_file(File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml'))
    config['local'] = { 'assets_dir' => File.join(@tmpdir, 'assets') }
    config_path = File.join(@tmpdir, 'porkadot.yaml')
    File.write(config_path, YAML.dump(config))

    capture_io do
      Porkadot::Assets::Addons.new(Porkadot::Config.new(config_path)).render
    end

    refute File.exist?(addon_path('storage-version-migrator'))
    kustomization = YAML.load_file(addon_path('kustomization.yaml'))
    assert_equal %w[flannel coredns metallb kubelet-serving-cert-approver], kustomization['resources']
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

  def coredns_deployment
    YAML.load_stream(File.read(addon_path('coredns/coredns.yaml')))
      .compact.find { |d| d['kind'] == 'Deployment' && d['metadata']['name'] == 'coredns' }
  end

  def dns_autoscaler_deployment
    YAML.load_stream(File.read(addon_path('coredns/dns-horizontal-autoscaler.yaml')))
      .compact.find { |d| d['kind'] == 'Deployment' }
  end

  def metallb_docs
    YAML.load_stream(File.read(addon_path('metallb/metallb.yaml'))).compact
  end

  def approver_deployment
    YAML.load_stream(File.read(addon_path('kubelet-serving-cert-approver/src.yaml')))
      .compact.find { |d| d['kind'] == 'Deployment' }
  end

  def pod_spec(ds)
    ds['spec']['template']['spec']
  end
end
