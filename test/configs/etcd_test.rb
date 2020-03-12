
require 'test_helper'

class PorkadotConfigsEtcdNodeTest < Minitest::Test
  include Porkadot::TestUtils

  def etcd_node name, raw={}
    raw = ::Porkadot::Raw.new(raw)
    return Porkadot::Configs::EtcdNode.new(self.mock_config, name, raw)
  end

  def test_etcd_path_contains_node_name
    node = etcd_node("node01")

    assert_includes node.etcd_path, 'node01'
  end
end
