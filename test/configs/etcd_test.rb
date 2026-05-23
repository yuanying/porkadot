
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

    assert_includes node.target_path, 'node01'
  end

  def test_listen_client_address_prefers_client_label
    node = etcd_node("node01", {
      labels: {
        Porkadot::ETCD_LISTEN_ADDRESS_LABEL => "10.0.0.1",
        Porkadot::ETCD_LISTEN_CLIENT_ADDRESS_LABEL => "10.0.0.2"
      }
    })

    assert_equal "10.0.0.2", node.listen_client_address
  end

  def test_listen_peer_address_prefers_peer_label
    node = etcd_node("node01", {
      labels: {
        Porkadot::ETCD_LEGACY_LISTEN_PEER_ADDRESS_LABEL => "10.0.0.2",
        Porkadot::ETCD_LISTEN_PEER_ADDRESS_LABEL => "10.0.0.3"
      }
    })

    assert_equal "10.0.0.3", node.listen_peer_address
  end

  def test_listen_peer_address_falls_back_to_legacy_label
    node = etcd_node("node01", {
      labels: {
        Porkadot::ETCD_LEGACY_LISTEN_PEER_ADDRESS_LABEL => "10.0.0.2"
      }
    })

    assert_equal "10.0.0.2", node.listen_peer_address
  end

  def test_listen_address_falls_back_to_shared_listen_label
    node = etcd_node("node01", {
      labels: {
        Porkadot::ETCD_LISTEN_ADDRESS_LABEL => "10.0.0.1"
      }
    })

    assert_equal "10.0.0.1", node.listen_client_address
  end

  def test_listen_address_uses_hostname_when_hostname_is_ip
    node = etcd_node("node01", {hostname: "10.0.0.1"})

    assert_equal "10.0.0.1", node.listen_client_address
  end

  def test_listen_address_uses_node_name_when_name_is_ip
    node = etcd_node("10.0.0.1")

    assert_equal "10.0.0.1", node.listen_client_address
  end

  def test_listen_address_falls_back_to_any_address
    node = etcd_node("node01", {hostname: "node01.example.com"})

    assert_equal "0.0.0.0", node.listen_client_address
  end

  def test_listen_peer_urls_use_peer_address
    node = etcd_node("node01", {
      labels: {
        Porkadot::ETCD_LISTEN_CLIENT_ADDRESS_LABEL => "10.0.0.2",
        Porkadot::ETCD_LISTEN_PEER_ADDRESS_LABEL => "10.0.0.3"
      }
    })

    assert_equal ["https://10.0.0.3:2380"], node.listen_peer_urls
  end
end
