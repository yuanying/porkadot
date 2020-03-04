
require 'test_helper'

class PorkadotConfigsEtcdTest < Minitest::Test
  include Porkadot::TestUtils

  def etcd name, raw={}
    raw = ::Porkadot::Raw.new(raw)
    return Porkadot::Configs::Etcd.new(self.mock_config, name, raw)
  end

  def test_etcd_path_contains_node_name
    node = etcd("node01")

    assert_includes node.etcd_path, 'node01'
  end
end
