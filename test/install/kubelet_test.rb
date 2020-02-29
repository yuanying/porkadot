
require 'test_helper'

class PorkadotInstallKubeletTest < Minitest::Test
  include Porkadot::TestUtils

  def kubelet name, raw={}
    raw = ::Porkadot::Raw.new(raw)
    config =  Porkadot::Configs::Kubelet.new(self.mock_config, name, raw)
    return Porkadot::Install::Kubelet.new(config)
  end

  def test_connection_has_user
    node = { connection: { user: 'hoge', hostname: '127.0.0.1' } }
    k = kubelet('test', node)
    assert k.connection[:user]
  end

  def test_connection_doesnt_has_address
    node = { connection: { user: 'hoge', hostname: '127.0.0.1' } }
    k = kubelet('test', node)
    assert k.connection[:hostname]
  end
end
