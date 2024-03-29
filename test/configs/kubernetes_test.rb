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

  def test_proxy_config_has_cluster_cidr
    assert_includes proxy.proxy_config, "clusterCIDR: #{k8s.networking.pod_subnet}"
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
