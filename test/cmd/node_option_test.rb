require "test_helper"
require "tmpdir"
require "fileutils"

# --node takes a key of nodes in porkadot.yaml. A value that matches none of
# them has to stop the command before anything runs on a node: it must not
# fall back to every node, as leaving --node out does.
class PorkadotCmdNodeOptionTest < Minitest::Test
  include Porkadot::TestUtils

  # SSHKit backend that records commands instead of running them over SSH.
  class RecordingBackend < SSHKit::Backend::Abstract
    class << self
      attr_accessor :commands
    end

    def upload!(_local, _remote, _options = {})
    end

    def download!(_remote, _local = nil, _options = {})
    end

    private

    def execute_command(cmd)
      self.class.commands << [host, cmd]
      cmd.exit_status = 0
    end
  end

  NODES = ['node01', '192.168.33.112', '192.168.33.113', 'node04', '192.168.33.115']
  MASTERS = ['node01', '192.168.33.112', '192.168.33.113']
  ETCD_MEMBERS = ['node01', '192.168.33.112']
  # node04's hostname. Not a key of nodes.
  UNKNOWN = '192.168.33.114'

  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = write_tmp_config(@tmpdir)
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

  # install kubelet, setup-containerd and setup-node

  KUBELET_COMMANDS = {
    ['install', 'kubelet'] => :install,
    ['setup-containerd'] => :setup_containerd,
    ['setup-node'] => :setup_default,
  }

  def test_kubelet_commands_with_unknown_node_fail_without_running
    KUBELET_COMMANDS.each do |args, method|
      calls = recording_kubelet_list(method) do
        status, err = main(*args, '--node', UNKNOWN)
        assert_equal 1, status, args.join(' ')
        assert_unknown_node err, UNKNOWN, NODES
      end
      assert_empty calls, args.join(' ')
    end
    assert_empty RecordingBackend.commands
  end

  def test_kubelet_commands_with_node_run_only_on_that_node
    KUBELET_COMMANDS.each do |args, method|
      calls = recording_kubelet_list(method) do
        assert_equal 0, main(*args, '--node', 'node04').first
      end
      assert_equal [['node04']], calls, args.join(' ')
    end
  end

  def test_kubelet_commands_without_node_run_on_every_node
    KUBELET_COMMANDS.each do |args, method|
      calls = recording_kubelet_list(method) do
        assert_equal 0, main(*args).first
      end
      assert_equal [NODES], calls, args.join(' ')
    end
  end

  def test_setup_commands_with_bootstrap_run_on_bootstrap_node
    KUBELET_COMMANDS.each do |args, method|
      next if args.first == 'install'
      calls = recording_kubelet_list(method) do
        assert_equal 0, main(*args, '--bootstrap').first
      end
      assert_equal [['bootstrap']], calls, args.join(' ')
    end
  end

  # install kubernetes

  KUBERNETES_TARGETS = {
    'all' => '',
    'apiserver' => 'kube-apiserver',
    'controller-manager' => 'kube-controller-manager',
    'scheduler' => 'kube-scheduler',
    'proxy' => 'kube-proxy',
  }

  def test_install_kubernetes_with_unknown_node_fails_without_running
    calls = recording_kubernetes do
      KUBERNETES_TARGETS.each_key do |sub|
        status, err = main('install', 'kubernetes', sub, '--node', UNKNOWN)
        assert_equal 1, status, sub
        assert_unknown_node err, UNKNOWN, NODES
      end
    end
    assert_empty calls
    assert_empty RecordingBackend.commands
  end

  # Its kubeconfig talks to the kube-apiserver on 127.0.0.1.
  def test_install_kubernetes_with_worker_node_fails_without_running
    calls = recording_kubernetes do
      status, err = main('install', 'kubernetes', '--node', 'node04')
      assert_equal 1, status
      assert_match(/^Node is not a control plane node: node04$/, err)
      assert_includes err, MASTERS.join(', ')
    end
    assert_empty calls
  end

  def test_install_kubernetes_with_node_runs_on_that_node
    calls = recording_kubernetes do
      KUBERNETES_TARGETS.each_key do |sub|
        assert_equal 0, main('install', 'kubernetes', sub, '--node', '192.168.33.112').first
      end
    end
    assert_equal KUBERNETES_TARGETS.values.map { |t| ['192.168.33.112', t] }, calls
  end

  def test_install_kubernetes_without_node_runs_on_bootstrap_node
    calls = recording_kubernetes do
      assert_equal 0, main('install', 'kubernetes').first
    end
    assert_equal [['bootstrap', '']], calls
  end

  # render kubelet and render etcd

  def test_render_with_unknown_node_fails_without_rendering
    [['kubelet', NODES], ['etcd', NODES]].each do |sub, nodes|
      status, err = main('render', sub, '--node', UNKNOWN)
      assert_equal 1, status, sub
      assert_unknown_node err, UNKNOWN, nodes
    end
    refute File.exist?(File.join(@tmpdir, 'assets', 'kubelet'))
  end

  def test_render_etcd_with_non_etcd_node_fails_without_rendering
    status, err = main('render', 'etcd', '--node', 'node04')
    assert_equal 1, status
    assert_match(/^Node is not an etcd member: node04$/, err)
    assert_includes err, ETCD_MEMBERS.join(', ')
    refute File.exist?(File.join(@tmpdir, 'assets', 'kubelet'))
  end

  def test_render_with_node_renders_only_that_node
    run_cli('render', 'certs', '--config', @config_path)
    nodes = File.join(@tmpdir, 'assets', 'kubelet')

    assert_equal 0, main('render', 'kubelet', '--node', 'node04').first
    assert_equal ['node04'], Dir.children(nodes)

    # etcd is rendered into the node's directory.
    assert_equal 0, main('render', 'etcd', '--node', '192.168.33.112').first
    assert_equal ['192.168.33.112', 'node04'], Dir.children(nodes).sort
    assert_equal ['addons'], Dir.children(File.join(nodes, '192.168.33.112'))
  end

  # etcd

  def test_etcd_commands_with_unknown_node_fail_without_running
    %w(backup start stop).each do |sub|
      status, err = main('etcd', sub, '--node', UNKNOWN, *etcd_args(sub))
      assert_equal 1, status, sub
      assert_unknown_node err, UNKNOWN, NODES
    end
    assert_empty RecordingBackend.commands
  end

  def test_etcd_commands_with_non_etcd_node_fail_without_running
    %w(backup start stop).each do |sub|
      status, err = main('etcd', sub, '--node', 'node04', *etcd_args(sub))
      assert_equal 1, status, sub
      assert_match(/^Node is not an etcd member: node04$/, err)
      assert_includes err, ETCD_MEMBERS.join(', ')
    end
    assert_empty RecordingBackend.commands
  end

  # rotate-certs

  def test_rotate_certs_with_unknown_node_fails_without_running
    %w(all etcd kubernetes kubelet-ca).each do |sub|
      status, err = main('rotate-certs', sub, '--node', UNKNOWN)
      assert_equal 1, status, sub
      assert_unknown_node err, UNKNOWN, NODES
    end
    assert_empty RecordingBackend.commands
  end

  def test_rotate_certs_kubernetes_with_worker_node_fails_without_running
    status, err = main('rotate-certs', 'kubernetes', '--node', 'node04')
    assert_equal 1, status
    assert_match(/^Node is not a control plane node: node04$/, err)
    assert_includes err, MASTERS.join(', ')
    assert_empty RecordingBackend.commands
  end

  def test_rotate_certs_kubelet_ca_with_node_runs_only_on_that_node
    run_cli('render', 'certs', '--config', @config_path)
    run_cli('render', 'kubelet', '--config', @config_path)
    assert_equal 0, main('rotate-certs', 'kubelet-ca', '--node', 'node04').first

    assert_equal ['192.168.33.114'], RecordingBackend.commands.map { |host, _| host.hostname }.uniq
  end

  private

  def etcd_args sub
    sub == 'backup' ? ['--path', File.join(@tmpdir, 'backup')] : []
  end

  # Runs exe/porkadot's entry point. Returns the exit status and stderr.
  def main(*args)
    status = nil
    _, err = capture_io do
      status = Porkadot::Cmd::Cli.main([*args, '--config', @config_path])
    end
    [status, err]
  end

  def assert_unknown_node err, name, nodes
    assert_match(/^Unknown node: #{Regexp.escape(name)}$/, err)
    assert_includes err, nodes.join(', ')
  end

  # Records the node names each call of method on Install::KubeletList gets,
  # instead of running it.
  def recording_kubelet_list method
    calls = []
    factory = lambda do |original, *args|
      original.call(*args).tap do |list|
        list.define_singleton_method(method) do |hosts: nil, force: false|
          calls << Array(hosts).map { |h| h.config.name }
        end
      end
    end
    stub_new(Porkadot::Install::KubeletList, factory) { yield }
    calls
  end

  # Records the node name and the target of each Install::Kubernetes#install.
  def recording_kubernetes
    calls = []
    fake = Object.new
    fake.define_singleton_method(:install) do |host, target = '', **_opts|
      calls << [host.config.name, target]
    end
    stub_new(Porkadot::Install::Kubernetes, ->(*_) { fake }) { yield }
    calls
  end

  # Makes klass.new call factory with the original new and the arguments.
  def stub_new klass, factory
    original = klass.method(:new)
    silence_warnings { klass.define_singleton_method(:new) { |*args| factory.call(original, *args) } }
    yield
  ensure
    silence_warnings { klass.singleton_class.send(:remove_method, :new) }
  end

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
