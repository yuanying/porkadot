require 'test_helper'

class PorkadotConfigsKubeletTest < Minitest::Test
  include Porkadot::TestUtils

  def kubelet name, raw={}
    raw = ::Porkadot::Raw.new(raw)
    return Porkadot::Configs::Kubelet.new(self.mock_config, name, raw)
  end

  def test_connection_default_user
    node = kubelet('test')

    assert_equal 'ubuntu', node.connection.user
  end

  def test_connection_user_override_by_node_connection
    node = { connection: { user: 'core' } }
    node = kubelet('test', node)

    assert_equal 'core', node.connection.user
  end

  def test_connection_hostname_by_name
    node = kubelet('test')

    assert_equal 'test', node.connection.hostname
  end

  def test_connection_hostname_by_hostname
    node = { hostname: 'hoge' }
    node = kubelet('test', node)

    assert_equal 'hoge', node.connection.hostname
  end

  def test_connection_hostname_by_connection_hostname
    node = { hostname: 'hoge' , connection: { hostname: 'fuga' }}
    node = kubelet('test', node)

    assert_equal 'fuga', node.connection.hostname
  end

  def test_connection_has_user_port_hostname_by_default
    node = kubelet('test')

    assert node.connection.hostname
    assert node.connection.user
    assert node.connection.port
  end

  def test_node01_labels_string
    config = self.mock_config('porkadot2.yaml')
    node = config.nodes['node01']
    assert_equal 'k8s.unstable.cloud/master,etcd.unstable.cloud/member=node01', node.labels_string
  end

  def test_node04_labels_string_should_be_blank
    config = self.mock_config('porkadot2.yaml')
    node = config.nodes['node04']
    assert_equal '', node.labels_string
  end

  def test_kubelet_config_cluster_domain
    config = self.mock_config('porkadot2.yaml')
    node = config.nodes['node04']
    assert_equal 'cluster.local', node.kubelet_config['clusterDomain']
    assert_equal '10.254.0.10', node.kubelet_config['clusterDNS'][0]
  end

  def test_kubelet_config_override
    config = self.mock_config('porkadot2.yaml')
    node01 = config.nodes['node01']
    node04 = config.nodes['node04']

    assert_nil node01.kubelet_config['failSwapOn']
    assert_equal true, node04.kubelet_config['failSwapOn']
    assert_equal true, node04.kubelet_config['featureGates']['NodeSwap']
    assert_equal false, node04.kubelet_config['featureGates']['CSIMigration']
  end
end
