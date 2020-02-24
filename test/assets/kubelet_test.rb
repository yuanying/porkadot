require 'test_helper'

class PorkadotAssetsKubeletTest < Minitest::Test
  include Porkadot::TestUtils

  def kubelet name, raw={}
    raw = ::Hashie::Mash.new(raw)
    config = Porkadot::Configs::Kubelet.new(self.mock_config, name, raw)
    return Porkadot::Assets::Kubelet.new(config)
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

  def test_connection_address_by_name
    node = kubelet('test')

    assert_equal 'test', node.connection.address
  end

  def test_connection_address_by_address
    node = { address: 'hoge' }
    node = kubelet('test', node)

    assert_equal 'hoge', node.connection.address
  end

  def test_connection_address_by_connection_address
    node = { address: 'hoge' , connection: { address: 'fuga' }}
    node = kubelet('test', node)

    assert_equal 'fuga', node.connection.address
  end
end
