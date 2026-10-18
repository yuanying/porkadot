
require 'test_helper'
require 'tmpdir'

class PorkadotInstallKubeletTest < Minitest::Test
  include Porkadot::TestUtils

  # SSHKit backend that records commands instead of running them over SSH.
  class RecordingBackend < SSHKit::Backend::Abstract
    class << self
      attr_accessor :commands
    end

    def upload!(_local, _remote, _options = {})
    end

    private

    def execute_command(cmd)
      self.class.commands << [host, cmd]
      cmd.exit_status = 0
    end
  end

  def kubelet name, raw={}
    raw = ::Porkadot::Raw.new(raw)
    config =  Porkadot::Configs::Kubelet.new(self.mock_config, name, raw)
    return Porkadot::Install::Kubelet.new(config)
  end

  def test_connection_has_user
    node = { connection: { user: 'hoge', hostname: '127.0.0.1' } }
    k = kubelet('test', node)
    assert k.connection[:user]
  end

  def test_connection_doesnt_has_address
    node = { connection: { user: 'hoge', hostname: '127.0.0.1' } }
    k = kubelet('test', node)
    assert k.connection[:hostname]
  end

  def test_install_always_runs_install_deps
    commands = record_install(force: false)

    deps = commands.select { |c| c.include?('install-deps.sh') }
    assert_equal 1, deps.size, commands.join("\n")
    refute_includes deps.first, '--force'
    refute commands.any? { |c| c.include?('/opt/bin/kubelet-') }, 'install should not check for the kubelet binary'
  end

  def test_install_passes_force_to_install_deps
    commands = record_install(force: true)

    deps = commands.select { |c| c.include?('install-deps.sh') }
    assert_equal 1, deps.size, commands.join("\n")
    assert_match %r{install-deps\.sh --force}, deps.first
  end

  private

  def record_install force:
    original_backend = SSHKit.config.backend
    original_output = SSHKit.config.output
    SSHKit.config.backend = RecordingBackend
    SSHKit.config.output = SSHKit::Formatter::BlackHole.new($stdout)
    RecordingBackend.commands = []

    Dir.mktmpdir do |dir|
      config = Porkadot::Config.new(write_tmp_config(dir))
      config.logger.level = Logger::WARN
      Porkadot::Install::KubeletList.new(config).install(hosts: nil, force: force)
    end

    RecordingBackend.commands
      .select { |host, _| host.hostname == '192.168.33.111' }
      .map { |_, cmd| cmd.to_s }
  ensure
    SSHKit.config.backend = original_backend
    SSHKit.config.output = original_output
  end
end
