require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

class PorkadotRenderKubeletTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = write_tmp_config(@tmpdir)
    run_cli('render', 'certs', '--config', @config_path)
    run_cli('render', 'kubelet', '--config', @config_path)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  # 1.37 deprecates the flags that the config file can set, and
  # --container-runtime-endpoint is the one porkadot used to pass.
  def test_kubelet_service_leaves_container_runtime_endpoint_to_config
    service = File.read(node_path('kubelet.service'))

    refute_match(/--container-runtime-endpoint/, service)
    assert_match %r{--config=/var/lib/kubelet/config\.yaml}, service
  end

  def test_kubelet_config_file_has_container_runtime_endpoint
    config = YAML.load_file(node_path('config.yaml'))

    assert_equal 'unix:///run/containerd/containerd.sock', config['containerRuntimeEndpoint']
  end

  private

  def node_path(file)
    File.join(@tmpdir, 'assets', 'kubelet', 'node01', file)
  end
end
