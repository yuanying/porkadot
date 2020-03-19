require 'test_helper'

class PorkadotConfigsLbTest < Minitest::Test
  include Porkadot::TestUtils

  def lb
    return Porkadot::Configs::Lb.new(self.mock_config)
  end

  def test_lb_has_config
    config =<<-"EOF"
address-pools:
- name: default
  protocol: layer2
  addresses:
  - 192.168.1.240-192.168.1.250
    EOF
    assert_equal config, lb.lb_config
  end

  def test_lb_has_type
    assert_equal 'metallb', lb.type
  end
end
