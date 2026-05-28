require 'tempfile'
require 'test_helper'

class PorkadotConfigValidatorTest < Minitest::Test
  include Porkadot::TestUtils

  def test_valid_fixture_returns_true
    assert_equal true, mock_config.validate!
  end

  def test_missing_control_plane_endpoint_raises_error
    config = config_with do |data|
      data['kubernetes'].delete('control_plane_endpoint')
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end
    assert_includes error.message, 'kubernetes.control_plane_endpoint is required'
  end

  def test_nodes_must_be_hash
    config = config_with do |data|
      data['nodes'] = ['node01']
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end
    assert_includes error.message, 'nodes must be a Hash'
  end

  def test_invalid_cidr_raises_error
    config = config_with do |data|
      data['kubernetes']['networking']['pod_subnet'] = 'invalid-cidr'
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end
    assert_includes error.message,
      'kubernetes.networking.pod_subnet contains invalid CIDR: invalid-cidr'
  end

  def test_unknown_addon_raises_error
    config = config_with do |data|
      data['addons'] ||= {}
      data['addons']['enabled'] = ['flannel', 'unknown-addon']
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end
    assert_includes error.message,
      'addons.enabled contains unknown addon: unknown-addon'
  end

  def test_empty_etcd_member_label_raises_error
    config = config_with do |data|
      data['nodes']['node01']['labels'][Porkadot::ETCD_MEMBER_LABEL] = nil
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end
    assert_includes error.message,
      'nodes.node01.labels.etcd.unstable.cloud/member must not be empty'
  end

  def test_invalid_connection_port_raises_error
    config = config_with do |data|
      data['connection']['port'] = 'ssh'
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end
    assert_includes error.message, 'connection.port must be an Integer'
  end

  def test_blank_connection_user_raises_error
    config = config_with do |data|
      data['connection']['user'] = ''
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end
    assert_includes error.message, 'connection.user is required'
  end

  def test_multiple_errors_are_aggregated
    config = config_with do |data|
      data['nodes'] = ['node01']
      data['connection']['user'] = ''
      data['connection']['port'] = 'ssh'
    end

    error = assert_raises(Porkadot::ConfigValidator::Error) do
      config.validate!
    end

    assert_includes error.message, 'nodes must be a Hash'
    assert_includes error.message, 'connection.user is required'
    assert_includes error.message, 'connection.port must be an Integer'
    assert_operator error.message.lines.size, :>=, 3
  end

  private

  def config_with
    data = YAML.load_file(File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml'))
    yield data

    file = Tempfile.new(['porkadot', '.yaml'])
    file.write(data.to_yaml)
    file.close

    Porkadot::Config.new(file.path)
  ensure
    file&.unlink
  end
end
