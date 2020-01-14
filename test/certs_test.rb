require "test_helper"

class CertsTest < Minitest::Test
  include Porkadot::TestUtils

  class CertUtils
    include Porkadot::Certs
    attr_reader :config

    def initialize config
      @config = config
    end
    def logger
      self.config.logger
    end
  end

  def setup
    @cert_utils = CertUtils.new(self.mock_config)
  end

  def test_additional_sans
    sans = @cert_utils.additional_sans
    assert_equal ["DNS:kubernetes", "DNS:kubernetes.default", "DNS:kubernetes.default.svc", "DNS:kubernetes.default.svc.cluster.local", "IP:127.0.0.1", "DNS:node01", "IP:192.168.33.101", "IP:192.168.33.111", "IP:192.168.33.112", "IP:192.168.33.113"], sans
  end
end
