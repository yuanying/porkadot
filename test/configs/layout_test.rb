require 'test_helper'

# Secrets live in the same tree as the other assets (assets/<group>/...).
class PorkadotConfigsLayoutTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @config = mock_config
    @assets = @config.assets_dir
  end

  def test_certs_are_rendered_under_assets_certs
    assert_equal File.join(@assets, 'certs', 'kubernetes', 'ca.key'), @config.certs.kubernetes.ca_key_path
    assert_equal File.join(@assets, 'certs', 'etcd', 'ca.crt'), @config.certs.etcd.ca_cert_path
    assert_equal File.join(@assets, 'certs', 'kubernetes', 'front-proxy-ca.key'), @config.certs.front_proxy.ca_key_path
  end

  def test_kubelet_bootstrap_key_is_next_to_its_cert
    kubelet = @config.nodes['node01']

    assert_equal File.join(@assets, 'kubelet', 'node01', 'bootstrap.key'), kubelet.bootstrap_key_path
    assert_equal File.dirname(kubelet.bootstrap_cert_path), File.dirname(kubelet.bootstrap_key_path)
  end

  def test_etcd_secrets_are_in_etcd_addon_dir
    etcd = @config.etcd_nodes['node01']
    dir = File.join(@assets, 'kubelet', 'node01', 'addons', 'etcd')

    assert_equal dir, etcd.target_path
    assert_equal File.join(dir, 'etcd.key'), etcd.etcd_key_path
    assert_equal File.join(dir, 'etcd.crt'), etcd.etcd_crt_path
    assert_equal File.join(dir, 'ca.crt'), etcd.ca_crt_path
  end

  def test_bootstrap_secrets_are_in_bootstrap_tree
    assert_equal File.join(@assets, 'bootstrap', 'bootstrap', 'secrets'), @config.bootstrap.secrets_path
    assert_equal File.join(@assets, 'bootstrap', 'kubelet', 'bootstrap.key'), @config.bootstrap.kubelet_config.bootstrap_key_path
  end

  def test_legacy_secrets_dir
    assert_equal File.join(@assets, 'secrets'), @config.legacy_secrets_dir
  end
end
