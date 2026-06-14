require "test_helper"

class PorkadotInstallRotateCertsTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @config = mock_config
    @rotator = Porkadot::Install::RotateCerts.new(@config)
  end

  def test_all_rotates_in_safe_order
    order = []
    @rotator.define_singleton_method(:etcd) { |node: nil| order << [:etcd, node] }
    @rotator.define_singleton_method(:kubernetes) { |node: nil| order << [:kubernetes, node] }
    @rotator.define_singleton_method(:kubelet_ca) { |node: nil| order << [:kubelet_ca, node] }

    @rotator.all(node: 'node01')

    assert_equal [[:etcd, 'node01'], [:kubernetes, 'node01'], [:kubelet_ca, 'node01']], order
  end

  def test_etcd_hosts_with_node_returns_only_requested_member
    hosts = @rotator.etcd_hosts('node01')

    assert_equal ['node01'], hosts.map { |host| host.config.name }
  end

  def test_etcd_hosts_rejects_non_etcd_node
    error = assert_raises(Porkadot::Error) do
      @rotator.etcd_hosts('node04')
    end

    assert_match(/not an etcd member/, error.message)
  end

  def test_cli_passes_node_to_etcd_rotation
    calls = []
    fake = Object.new
    fake.define_singleton_method(:etcd) { |node: nil| calls << [:etcd, node] }

    original_new = Porkadot::Install::RotateCerts.method(:new)
    silence_warnings { Porkadot::Install::RotateCerts.define_singleton_method(:new) { |_| fake } }
    begin
      capture_io do
        Porkadot::Cmd::Cli.start([
          'rotate-certs',
          'etcd',
          '--node',
          'node01',
          '--config',
          File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml')
        ])
      end
    ensure
      silence_warnings { Porkadot::Install::RotateCerts.define_singleton_method(:new) { |*args| original_new.call(*args) } }
    end

    assert_equal [[:etcd, 'node01']], calls
  end

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
