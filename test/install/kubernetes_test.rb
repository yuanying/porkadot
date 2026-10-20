require "test_helper"

class PorkadotInstallKubernetesTest < Minitest::Test
  include Porkadot::TestUtils

  # SSHKit backend that records commands instead of running them over SSH.
  class RecordingBackend < SSHKit::Backend::Abstract
    class << self
      attr_accessor :commands
    end

    def upload!(_local, _remote, _options = {}); end

    private

    def execute_command(cmd)
      self.class.commands << cmd.to_command
      cmd.exit_status = 0
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir
    config_path = copy_rendered_kubernetes(@tmpdir)
    @config = Porkadot::Config.new(config_path)
    @config.logger.level = Logger::WARN
    @host = Porkadot::Install::Bootstrap.new(@config).host

    @original_backend = SSHKit.config.backend
    @original_output = SSHKit.config.output
    SSHKit.config.backend = RecordingBackend
    SSHKit.config.output = SSHKit::Formatter::BlackHole.new($stdout)
    RecordingBackend.commands = []
  end

  def teardown
    SSHKit.config.backend = @original_backend
    SSHKit.config.output = @original_output
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def install_command
    RecordingBackend.commands.find { |c| c.include?('kubernetes/install.sh') }
  end

  def test_install_waits_for_the_apiserver_by_default
    Porkadot::Install::Kubernetes.new(@config).install(@host)

    assert_includes install_command, 'KUBE_WAIT_APISERVER="true"'
    assert_includes install_command, "KUBE_APISERVER_TIMEOUT=\"#{Porkadot::Install::Kubernetes::DEFAULT_APISERVER_TIMEOUT}\""
  end

  def test_install_passes_the_timeout
    Porkadot::Install::Kubernetes.new(@config).install(@host, apiserver_timeout: 42)

    assert_includes install_command, 'KUBE_APISERVER_TIMEOUT="42"'
  end

  def test_install_can_skip_the_wait
    Porkadot::Install::Kubernetes.new(@config).install(@host, wait_apiserver: false)

    assert_includes install_command, 'KUBE_WAIT_APISERVER="false"'
  end

  def test_bootstrap_kubernetes_does_not_wait_for_the_apiserver
    run_cli('install', 'bootstrap', 'kubernetes', '--config', @config.path)

    assert_includes install_command, 'KUBE_WAIT_APISERVER="false"'
  end

  def test_install_kubernetes_waits_for_the_apiserver
    run_cli('install', 'kubernetes', '--config', @config.path, '--apiserver-timeout', '30')

    assert_includes install_command, 'KUBE_WAIT_APISERVER="true"'
    assert_includes install_command, 'KUBE_APISERVER_TIMEOUT="30"'
  end
end
