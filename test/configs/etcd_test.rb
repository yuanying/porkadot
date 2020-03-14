
require 'test_helper'

class PorkadotConfigsEtcdTest < Minitest::Test
  include Porkadot::TestUtils

  def etcd
    return Porkadot::Configs::Etcd.new(self.mock_config)
  end

  def test_advertise_urls
    assert_equal ["https://192.168.33.111:2379", "https://192.168.33.112:2379"], etcd.advertise_client_urls
  end
end

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
