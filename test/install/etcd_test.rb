require "test_helper"
require "tmpdir"

class PorkadotInstallEtcdTest < Minitest::Test
  include Porkadot::TestUtils

  # SSHKit backend that records commands instead of running them over SSH.
  class RecordingBackend < SSHKit::Backend::Abstract
    class << self
      attr_accessor :commands, :uploads, :downloads, :responder, :curl_status, :etcd_healthy
    end

    def upload!(local, remote, _options = {})
      self.class.uploads << [host.hostname, local, remote]
    end

    def download!(remote, local = nil, _options = {})
      self.class.downloads << [host.hostname, remote, local]
      # Simulates a download that leaves the file world-readable.
      File.open(local, 'w', 0644) { |f| f.write('snapshot') } if local.is_a?(String)
    end

    private

    def execute_command(cmd)
      self.class.commands << [host, cmd]
      stdout = self.class.responder ? self.class.responder.call(host, cmd).to_s : ''
      cmd.on_stdout(nil, stdout) unless stdout.empty?
      cmd.exit_status = 0
      cmd.exit_status = self.class.curl_status || 0 if cmd.to_s.include?('curl')
      cmd.exit_status = 1 if cmd.to_s.include?('endpoint health') && self.class.etcd_healthy == false
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
    RecordingBackend.curl_status = nil
    RecordingBackend.etcd_healthy = nil
  end

  def restore_with_snapshot
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'etcd.db')
      File.write(path, 'snapshot')
      @kubelets.restore_etcd path: path
    end
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

  # Returns the command matching pattern and whether `as user: 'root'` wraps it.
  def find_command hostname, pattern
    cmd = RecordingBackend.commands
      .select { |host, _| host.hostname == hostname }
      .map(&:last)
      .find { |c| c.to_s.include?(pattern) }
    return [nil, false] unless cmd
    [cmd.to_s, cmd.to_command.start_with?('sudo -u root ')]
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

  # etcdctl 3.6 has no snapshot restore; etcdutl has it since 3.5.
  def test_restore_etcd_uses_etcdutl
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'etcd.db')
      File.write(path, 'snapshot')
      @kubelets.restore_etcd path: path
    end

    restore, as_root = find_command('192.168.33.111', 'snapshot restore')
    assert_match %r{ /opt/bin/etcdutl snapshot restore }, restore
    assert as_root, 'snapshot restore was not run as root'
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

  # Without a bump the revision goes back to the snapshot's, and clients
  # watching from a later revision miss everything in between.
  def test_restore_etcd_bumps_and_compacts_the_revision
    restore_with_snapshot

    restore, = find_command('192.168.33.111', 'snapshot restore')
    assert_includes restore, '--bump-revision 1000000000 --mark-compacted'
  end

  # etcdutl has the two flags since 3.5.10.
  def test_restore_etcd_without_bump_for_older_etcd
    @config.etcd.raw.image_tag = '3.5.9-0'
    restore_with_snapshot

    restore, = find_command('192.168.33.111', 'snapshot restore')
    refute_includes restore, '--bump-revision'
    refute_includes restore, '--mark-compacted'
  end

  def test_restore_bumps_revision_follows_image_tag
    { '3.5.9-0' => false, '3.5.10-0' => true, '3.5.34-0' => true, '3.6.15-0' => true, 'latest' => true }.each do |tag, expected|
      @config.etcd.raw.image_tag = tag
      assert_equal expected, @config.etcd.restore_bumps_revision?, tag
    end
  end

  # --- after restore ---

  MASTERS = ['192.168.33.111', '192.168.33.112', 'node03']

  # Fake crictl: each master runs an old container per component until it is
  # stopped, then the kubelet's new one. node03 runs no controller-manager
  # nor scheduler. restart: false keeps the old containers forever.
  def control_plane_responder restart: true, ready: true
    stopped = []
    lambda do |host, cmd|
      cmd = cmd.to_s
      if cmd.include?('crictl stop')
        stopped << [host.hostname, cmd.split.last]
        ''
      elsif (m = cmd.match(/crictl ps -q --name \^([\w-]+)\$/))
        name = m[1]
        next '' if host.hostname == 'node03' && name != 'kube-apiserver'
        old = "old-#{name}-#{host.hostname}"
        (restart && stopped.include?([host.hostname, old])) ? "new-#{name}-#{host.hostname}" : old
      elsif cmd.include?('curl')
        RecordingBackend.curl_status = ready ? 0 : 1
        ''
      else
        ''
      end
    end
  end

  def test_restart_control_plane_replaces_apiservers_first
    RecordingBackend.responder = control_plane_responder
    @kubelets.restart_control_plane

    stops = RecordingBackend.commands.map { |h, c| [h.hostname, c.to_s] }.select { |_, c| c.include?('crictl stop') }
    apiserver = stops.select { |_, c| c.include?('kube-apiserver') }
    others = stops.reject { |_, c| c.include?('kube-apiserver') }
    assert_equal MASTERS.sort, apiserver.map(&:first).sort
    assert_equal ['192.168.33.111', '192.168.33.112'] * 2, others.map(&:first)
    assert_operator stops.index(apiserver.last), :<, stops.index(others.first)
    assert others.any? { |_, c| c.include?('kube-controller-manager') }
    assert others.any? { |_, c| c.include?('kube-scheduler') }
  end

  def test_restart_control_plane_waits_for_each_apiserver_to_be_ready
    RecordingBackend.responder = control_plane_responder
    @kubelets.restart_control_plane

    MASTERS.each do |host|
      cmds = commands_for(host)
      stop = cmds.index { |c| c.include?('crictl stop old-kube-apiserver') }
      readyz = cmds.index { |c| c.include?('curl -skf https://127.0.0.1:6443/readyz') }
      assert readyz, "readyz was not checked on #{host}"
      assert_operator stop, :<, readyz
    end
  end

  def test_restart_control_plane_runs_crictl_as_root
    RecordingBackend.responder = control_plane_responder
    @kubelets.restart_control_plane

    stop = RecordingBackend.commands.map(&:last).find { |c| c.to_s.include?('crictl stop') }
    assert_includes stop.to_command, 'sudo -u root ', 'crictl stop was not run as root'
  end

  def test_restart_control_plane_times_out_when_kubelet_does_not_restart
    RecordingBackend.responder = control_plane_responder(restart: false)
    no_wait(@kubelets)

    error = assert_raises(Porkadot::Error) { @kubelets.restart_control_plane(timeout: 0) }
    assert_match(/kube-apiserver on 192\.168\.33\.111/, error.message)
    assert_match(/crictl ps -a --name kube-apiserver/, error.message)
    refute all_commands.any? { |c| c.include?('crictl stop old-kube-controller-manager') }
  end

  def test_restart_control_plane_times_out_when_apiserver_is_not_ready
    RecordingBackend.responder = control_plane_responder(ready: false)
    no_wait(@kubelets)

    error = assert_raises(Porkadot::Error) { @kubelets.restart_control_plane(timeout: 0) }
    assert_match(/readyz/, error.message)
  end

  def test_wait_etcd_health_times_out
    RecordingBackend.responder = lambda do |_, cmd|
      RecordingBackend.etcd_healthy = false if cmd.to_s.include?('endpoint health')
      ''
    end
    no_wait(@kubelets)

    error = assert_raises(Porkadot::Error) { @kubelets.wait_etcd_health(timeout: 0) }
    assert_match(/etcd health on 192\.168\.33\.111/, error.message)
  end

  def test_wait_etcd_health_checks_every_member_as_root
    @kubelets.wait_etcd_health

    ['192.168.33.111', '192.168.33.112'].each do |host|
      health, as_root = find_command(host, 'endpoint health')
      assert health, "endpoint health was not checked on #{host}"
      assert as_root
    end
  end

  def test_etcd_restore_command_restarts_the_control_plane_after_etcd
    RecordingBackend.responder = control_plane_responder
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'etcd-2026-10-20T00:00:00+00:00.db'), 'snapshot')
      run_cli('etcd', 'restore', '--config', @config.path, '--path', dir, '--timeout', '30')
    end

    cmds = all_commands
    restore = cmds.index { |c| c.include?('snapshot restore') }
    start = cmds.index { |c| c.include?('/opt/porkadot/etcd-server.yaml /etc/kubernetes/manifests/') }
    health = cmds.index { |c| c.include?('endpoint health') }
    stop_apiserver = cmds.index { |c| c.include?('crictl stop old-kube-apiserver') }
    assert restore && start && health && stop_apiserver, cmds.inspect
    assert_operator restore, :<, start
    assert_operator start, :<, health
    assert_operator health, :<, stop_apiserver
  end

  def no_wait kubelets
    kubelets.define_singleton_method(:pause) {}
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

  # The etcd client key is readable only by root, so etcdctl must run as
  # root and the snapshot must be handed back to the connection user.
  def test_backup_etcd_saves_snapshot_as_root
    RecordingBackend.responder = backup_responder
    Dir.mktmpdir do |dir|
      @kubelets.backup_etcd host: 'node01', path: File.join(dir, 'etcd.db')
    end

    save, as_root = find_command('192.168.33.111', 'snapshot save')
    assert save, 'snapshot save was not executed'
    assert as_root, 'snapshot save was not run as root'
    assert_includes save, '--cacert /etc/etcd/pki/ca.crt'
    assert_includes save, 'kube_temp/kubelet/etcd.db'
  end

  def test_backup_etcd_hands_snapshot_to_connection_user_with_mode_600
    RecordingBackend.responder = backup_responder
    Dir.mktmpdir do |dir|
      @kubelets.backup_etcd host: 'node01', path: File.join(dir, 'etcd.db')
    end

    commands = commands_for('192.168.33.111')
    save = commands.index { |c| c.include?('snapshot save') }
    chown = commands.index { |c| c.include?('chown 1000:1001 ./kube_temp/kubelet/etcd.db') }
    chmod = commands.index { |c| c.include?('chmod 0600 ./kube_temp/kubelet/etcd.db') }
    assert chown, "snapshot was not chowned: #{commands.inspect}"
    assert chmod, "snapshot was not chmoded: #{commands.inspect}"
    assert find_command('192.168.33.111', 'chown').last, 'chown was not run as root'
    assert_operator save, :<, chown
    assert_operator save, :<, chmod
  end

  def test_backup_etcd_removes_remote_snapshot_after_download
    RecordingBackend.responder = backup_responder
    Dir.mktmpdir do |dir|
      @kubelets.backup_etcd host: 'node01', path: File.join(dir, 'etcd.db')
    end

    assert_equal [['192.168.33.111', './kube_temp/kubelet/etcd.db']],
      RecordingBackend.downloads.map { |h, remote, _| [h, remote] }
    rm = commands_for('192.168.33.111').last
    assert_includes rm, 'rm -f ./kube_temp/kubelet/etcd.db'
  end

  def test_backup_etcd_writes_local_snapshot_with_mode_600
    RecordingBackend.responder = backup_responder
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'etcd.db')
      @kubelets.backup_etcd host: 'node01', path: path

      assert_equal 0600, File.stat(path).mode & 0777
    end
  end

  def test_rotate_certs_waits_for_etcd_health_as_root
    rotator = Porkadot::Install::RotateCerts.new(@config)
    host = @kubelets['node01']
    rotator.send(:wait_etcd_health, host, @kubelets.etcd_options)

    health, as_root = find_command('192.168.33.111', 'endpoint health')
    assert health, 'endpoint health was not checked'
    assert as_root, 'endpoint health was not checked as root'
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

  def backup_responder
    lambda do |_host, cmd|
      case cmd.to_s
      when /\bid -u\b/ then '1000'
      when /\bid -g\b/ then '1001'
      else ''
      end
    end
  end

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
