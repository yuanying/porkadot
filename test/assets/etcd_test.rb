require 'test_helper'

class PorkadotAssetsEtcdTest < Minitest::Test
  include Porkadot::TestUtils

  def etcds
    return Porkadot::Assets::EtcdList.new(self.mock_config)
  end

  def test_node01_is_etcd_node
    node = etcds['node01']

    assert node
  end

  def test_node04_is_not_etcd_node
    node = etcds['node04']

    assert_nil node
  end

  def test_etcd_list_has_two_nodes
    assert_equal 2, etcds.nodes.size
  end
end
