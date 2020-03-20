require 'test_helper'

class PorkadotConfigsK8sTest < Minitest::Test
  include Porkadot::TestUtils

  def k8s
    return Porkadot::Configs::Kubernetes.new(self.mock_config)
  end

  def proxy
    return self.k8s.proxy
  end

  def apiserver
    return self.k8s.apiserver
  end

  def test_endpoint_host_and_port
    assert_equal ['192.168.33.101', '6443'], k8s.control_plane_endpoint_host_and_port
  end

  def test_proxy_config_has_cluster_cidr
    assert_includes proxy.proxy_config, "clusterCIDR: #{k8s.networking.service_subnet}"
  end

end
