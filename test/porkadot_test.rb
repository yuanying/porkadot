require "test_helper"

class PorkadotTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Porkadot::VERSION
  end
end
