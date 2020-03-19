require 'test_helper'

class PorkadotConfigsBootstrapTest < Minitest::Test
  include Porkadot::TestUtils

  def bootstrap config='porkadot.yaml'
    Porkadot::Configs::Bootstrap.new(self.mock_config(config))
  end

  def test_default_node
    assert_equal 'node01', bootstrap.node.hostname
  end

  def test_node_specified
    assert_equal 'node04', bootstrap('porkadot2.yaml').node.hostname
  end

end
