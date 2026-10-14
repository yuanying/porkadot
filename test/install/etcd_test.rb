require "test_helper"
require "tmpdir"

class PorkadotInstallEtcdTest < Minitest::Test
  include Porkadot::TestUtils

  # SSHKit backend that records commands instead of running them over SSH.
  class RecordingBackend < SSHKit::Backend::Abstract
    class << self
      attr_accessor :commands, :uploads, :downloads, :responder
    end

    def upload!(local, remote, _options = {})
      self.class.uploads << [host.hostname, local, remote]
    end

    def download!(remote, local = nil, _options = {})
      self.class.downloads << [host.hostname, remote, local]
    end

    private

    def execute_command(cmd)
      self.class.commands << [host, cmd]
      stdout = self.class.responder ? self.class.responder.call(host, cmd).to_s : ''
      cmd.on_stdout(nil, stdout) unless stdout.empty?
      cmd.exit_status = 0
    end
  end

  def setup
    @config = mock_config
    @config.logger.level = Logger::WARN
    @kubelets = Porkadot::Install::KubeletList.new(@config)

    @original_backend = SSHKit.config.backend
    @original_output = SSHKit.config.output
    SSHKit.config.backend = RecordingBackend
    SSHKit.config.output = SSHKit::Formatter::BlackHole.new($stdout)
    RecordingBackend.commands = []
    RecordingBackend.uploads = []
    RecordingBackend.downloads = []
    RecordingBackend.responder = nil
  end

  def teardown
    SSHKit.config.backend = @original_backend
    SSHKit.config.output = @original_output
  end

  def commands_for hostname
    RecordingBackend.commands
      .select { |host, _| host.hostname == hostname }
      .map { |_, cmd| cmd.to_s }
  end

  def all_commands
    RecordingBackend.commands.map { |_, cmd| cmd.to_s }
  end

  # --- restore ---

  def test_restore_etcd_restores_each_member_into_var_lib_etcd
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'etcd.db')
      File.write(path, 'snapshot')
      @kubelets.restore_etcd path: path
    end

    initial_cluster = 'node01=https://192.168.33.111:2380,node02=https://192.168.33.112:2380'
    {
      '192.168.33.111' => 'node01',
      '192.168.33.112' => 'node02',
    }.each do |hostname, member|
      restore = commands_for(hostname).find { |c| c.include?('snapshot restore') }
      assert restore, "snapshot restore was not executed on #{hostname}"
      assert_includes restore, '--data-dir /var/lib/etcd'
      assert_includes restore, "--name #{member}"
      assert_includes restore, "--initial-cluster #{initial_cluster}"
      assert_includes restore, "--initial-advertise-peer-urls https://#{hostname}:2380"
    end
  end

  def test_restore_etcd_uses_same_values_as_etcd_server_manifest
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'etcd.db')
      File.write(path, 'snapshot')
      @kubelets.restore_etcd path: path
    end

    @config.etcd_nodes.each do |name, node|
      hostname = @config.nodes[name].connection.hostname
      restore = commands_for(hostname).find { |c| c.include?('snapshot restore') }
      assert_includes restore, "--name #{node.member_name}"
      assert_includes restore, "--initial-cluster #{node.initial_cluster.map { |k, v| "#{k}=#{v}" }.join(',')}"
      assert_includes restore, "--initial-advertise-peer-urls #{node.advertise_peer_urls.join(',')}"
    end
  end

  def test_restore_etcd_moves_old_data_dir_under_etcd_temp
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'etcd.db')
      File.write(path, 'snapshot')
      @kubelets.restore_etcd path: path
    end

    mv = commands_for('192.168.33.111').find { |c| c.include?('mv /var/lib/etcd') }
    assert mv, 'old data dir was not moved away'
    assert_match %r{mv /var/lib/etcd /opt/porkadot/data-}, mv
    refute_includes all_commands.join("\n"), '${ETCD_TEMP}'
  end

  # --- stop / start ---

  def test_stop_etcd_moves_manifest_to_etcd_temp
    calls = Hash.new(0)
    RecordingBackend.responder = lambda do |host, cmd|
      next '' unless cmd.to_s.include?('crictl ps')
      calls[host.hostname] += 1
      calls[host.hostname] == 1 ? 'container-id' : ''
    end

    @kubelets.stop_etcd hosts: 'node01'

    mv = commands_for('192.168.33.111').find { |c| c.include?('mv /etc/kubernetes/manifests/etcd-server.yaml') }
    assert mv, 'manifest was not moved away'
    assert_includes mv, 'mv /etc/kubernetes/manifests/etcd-server.yaml /opt/porkadot/etcd-server.yaml'
    refute_includes all_commands.join("\n"), '${ETCD_TEMP}'
  end

  def test_start_etcd_moves_manifest_back_from_etcd_temp
    @kubelets.start_etcd hosts: 'node01'

    mv = commands_for('192.168.33.111').find { |c| c.include?('etcd-server.yaml') && c.include?(' mv ') }
    assert mv, 'manifest was not moved back'
    assert_includes mv, 'mv /opt/porkadot/etcd-server.yaml /etc/kubernetes/manifests/etcd-server.yaml'
    refute_includes all_commands.join("\n"), '${ETCD_TEMP}'
  end

  # --- --node resolution ---

  def test_stop_etcd_with_node_uses_connection_settings_from_config
    @kubelets.stop_etcd hosts: '192.168.33.112'

    hosts = RecordingBackend.commands.map(&:first).uniq
    assert_equal ['192.168.33.112'], hosts.map(&:hostname)
    assert_kind_of Porkadot::Install::Kubelet, hosts.first
    assert_equal 'ubuntu', hosts.first.user
  end

  def test_start_etcd_with_node_uses_connection_settings_from_config
    @kubelets.start_etcd hosts: 'node01'

    hosts = RecordingBackend.commands.map(&:first).uniq
    assert_equal ['192.168.33.111'], hosts.map(&:hostname)
    assert_equal 'ubuntu', hosts.first.user
  end

  def test_backup_etcd_with_node_uses_connection_settings_from_config
    Dir.mktmpdir do |dir|
      @kubelets.backup_etcd host: '192.168.33.112', path: File.join(dir, 'etcd.db')
    end

    hosts = RecordingBackend.commands.map(&:first).reject(&:local?).uniq
    assert_equal ['192.168.33.112'], hosts.map(&:hostname)
    assert_equal 'ubuntu', hosts.first.user
    assert_equal ['192.168.33.112'], RecordingBackend.downloads.map(&:first)
  end

  def test_backup_etcd_without_node_uses_first_etcd_member
    Dir.mktmpdir do |dir|
      @kubelets.backup_etcd path: File.join(dir, 'etcd.db')
    end

    hosts = RecordingBackend.commands.map(&:first).reject(&:local?).uniq
    assert_equal ['192.168.33.111'], hosts.map(&:hostname)
  end

  def test_etcd_command_with_unknown_node_raises_error
    [
      -> { @kubelets.stop_etcd hosts: 'unknown' },
      -> { @kubelets.start_etcd hosts: 'unknown' },
      -> { @kubelets.backup_etcd host: 'unknown', path: '/nonexistent/etcd.db' },
    ].each do |call|
      error = assert_raises(Porkadot::Error) { call.call }
      assert_match(/Unknown node: unknown/, error.message)
    end
    assert_empty RecordingBackend.commands
  end

  def test_etcd_command_with_non_etcd_node_raises_error
    error = assert_raises(Porkadot::Error) { @kubelets.stop_etcd hosts: 'node04' }
    assert_match(/not an etcd member: node04/, error.message)
    assert_empty RecordingBackend.commands
  end

  def test_cli_stop_passes_node_to_kubelet_list
    calls = []
    fake = Object.new
    fake.define_singleton_method(:stop_etcd) { |hosts: nil| calls << hosts }

    original_new = Porkadot::Install::KubeletList.method(:new)
    silence_warnings { Porkadot::Install::KubeletList.define_singleton_method(:new) { |_| fake } }
    begin
      capture_io do
        Porkadot::Cmd::Cli.start([
          'etcd', 'stop', '--node', 'node01',
          '--config', File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml')
        ])
      end
    ensure
      silence_warnings { Porkadot::Install::KubeletList.define_singleton_method(:new) { |*args| original_new.call(*args) } }
    end

    assert_equal ['node01'], calls
  end

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
