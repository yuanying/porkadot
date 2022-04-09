require 'test_helper'

class PorkadotConfigsLbTest < Minitest::Test
  include Porkadot::TestUtils

  def lb
    return Porkadot::Configs::Addons.new(self.mock_config).metallb
  end

  def test_lb_has_config
    config =<<-"EOF"
address-pools:
- name: default
  protocol: layer2
  addresses:
  - 192.168.1.240-192.168.1.250
    EOF
    assert_equal config, lb.config
  end
end
