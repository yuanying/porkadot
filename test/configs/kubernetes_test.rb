require 'test_helper'

class PorkadotConfigsK8sTest < Minitest::Test
  include Porkadot::TestUtils

  DUALSTACK_CONFIG='porkadot2.yaml'
  IPV6_CONFIG='porkadot3.yaml'

  def k8s(file='porkadot.yaml')
    return Porkadot::Configs::Kubernetes.new(self.mock_config(file))
  end

  def proxy
    return self.k8s.proxy
  end

  def apiserver
    return self.k8s.apiserver
  end

  def networking
    return self.k8s.networking
  end

  def test_endpoint_host_and_port
    assert_equal ['192.168.33.101', '6443'], k8s.control_plane_endpoint_host_and_port
  end

  def test_explicit_accessors
    assert_equal 'porkadot', k8s.cluster_name
    assert_equal '192.168.33.101:6443', k8s.control_plane_endpoint
    assert_equal 'v1.17.2', k8s.kubernetes_version
    assert_equal 'v1.28.0', k8s.crictl_version
    assert_equal 'registry.k8s.io', k8s.image_repository
    assert_nil k8s.log_level
  end

  def test_networking_explicit_accessors
    assert_equal '10.254.0.0/24', networking.service_subnet
    assert_equal '10.244.0.0/16', networking.pod_subnet
    assert_equal 'cluster.local', networking.dns_domain
    assert_equal [], networking.additional_domains
    assert_equal 'v0.9.1', networking.cni_version
  end

  def test_apiserver_explicit_accessors
    assert_equal 6443, apiserver.bind_port
    assert_equal ['--bind-address=127.0.0.1'], apiserver.extra_args
    assert_equal 2, apiserver.log_level
  end

  def test_scheduler_explicit_accessors
    assert_nil k8s.scheduler.extra_args
    assert_equal 2, k8s.scheduler.log_level
  end

  def test_controller_manager_explicit_accessors
    assert_nil k8s.controller_manager.extra_args
    assert_equal 2, k8s.controller_manager.log_level
  end

  def test_proxy_config_has_cluster_cidr
    assert_includes proxy.proxy_config, "clusterCIDR: #{k8s.networking.pod_subnet}"
  end

  def test_proxy_config_does_not_mutate_raw_config
    proxy.proxy_config

    assert_nil proxy.raw.config['clusterCIDR']
  end

  def test_proxy_config_kubeconfig_argument_only_changes_returned_yaml
    returned = YAML.load(proxy.proxy_config('/tmp/kube-proxy.conf'))

    assert_equal '/tmp/kube-proxy.conf', returned['clientConnection']['kubeconfig']
    assert_equal '/var/lib/kube-proxy/kubeconfig.conf', proxy.raw.config['clientConnection']['kubeconfig']
  end

  def test_proxy_config_without_kubeconfig_preserves_default
    returned = YAML.load(proxy.proxy_config)

    assert_equal '/var/lib/kube-proxy/kubeconfig.conf', returned['clientConnection']['kubeconfig']
  end

  def test_apiserver_default_args
    assert_includes apiserver.default_args, '--v'
    assert_includes apiserver.default_args, '--advertise-address'
  end

  def test_apiserver_args
    assert_equal '2', apiserver.args['--v']
  end

  def test_default_service_subnet
    assert_equal '10.254.0.0/24', k8s.networking.default_service_subnet
  end

  def test_default_service_subnet_dualstack
    assert_equal '10.254.0.0/24', k8s(DUALSTACK_CONFIG).networking.default_service_subnet
  end

  def test_default_service_subnet_ipv6
    assert_equal '2001:db8:1::/108', k8s(IPV6_CONFIG).networking.default_service_subnet
  end

  def test_dns_ip
    assert_equal '10.254.0.10', "#{k8s.networking.dns_ip}"
  end

  def test_dns_ip_dualstack
    assert_equal '10.254.0.10', "#{k8s(DUALSTACK_CONFIG).networking.dns_ip}"
  end

  def test_dns_ip_v6
    assert_equal '2001:db8:1::a', "#{k8s(IPV6_CONFIG).networking.dns_ip}"
  end

  def test_podv4subnet
    assert_equal '10.244.0.0/16', "#{k8s.networking.pod_v4subnet}"
  end

  def test_podv6subnet
    assert_nil k8s.networking.pod_v6subnet
  end

  def test_podv4subnet_dualstack
    assert_equal '10.244.0.0/16', "#{k8s(DUALSTACK_CONFIG).networking.pod_v4subnet}"
  end

  def test_podv6subnet_dualstack
    assert_equal '2008:db8::/48', "#{k8s(DUALSTACK_CONFIG).networking.pod_v6subnet}"
  end

end
