require "test_helper"

class PorkadotInstallBootstrapTest < Minitest::Test
  include Porkadot::TestUtils

  MASTERS = ['192.168.33.111', '192.168.33.112', '192.168.33.113']

  # SSHKit backend that records commands instead of running them over SSH.
  # The responder returns [stdout, exit_status] for each command.
  class RecordingBackend < SSHKit::Backend::Abstract
    class << self
      attr_accessor :commands, :responder
    end

    def upload!(_local, _remote, _options = {}); end

    private

    def execute_command(cmd)
      self.class.commands << cmd.to_s
      stdout, status = self.class.responder.call(cmd.to_s)
      cmd.on_stdout(nil, stdout.to_s) unless stdout.to_s.empty?
      cmd.exit_status = status || 0
    end
  end

  # Fake control plane. Each attribute says what the bootstrap host sees.
  class FakeCluster
    attr_accessor :readyz, :endpoints, :deployments, :vip_after_cleanup
    attr_reader :cleaned_up

    def initialize
      @readyz = MASTERS.map { |m| [m, true] }.to_h
      @endpoints = MASTERS.map { |m| endpoint(m, true) } + [bootstrap_endpoint('node01', true)]
      @deployments = { 'kube-controller-manager' => 2, 'kube-scheduler' => 2 }
      @vip_after_cleanup = true
      @cleaned_up = false
    end

    def endpoint node_name, ready, pod: "kube-apiserver-#{node_name.tr('.', '-')}"
      {
        'addresses' => [node_name],
        'conditions' => ready.nil? ? {} : { 'ready' => ready },
        'nodeName' => node_name,
        'targetRef' => { 'kind' => 'Pod', 'name' => pod, 'namespace' => 'kube-system' },
      }
    end

    def bootstrap_endpoint node_name, ready
      endpoint(node_name, ready, pod: "bootstrap-kube-apiserver-#{node_name}")
    end

    def call cmd
      case cmd
      when /cleanup\.sh/
        @cleaned_up = true
        ['', 0]
      when %r{curl -skf https://192\.168\.33\.101:6443/readyz}
        [nil, (!@cleaned_up || @vip_after_cleanup) ? 0 : 1]
      when %r{curl -skf https://([^/]+):6443/readyz}
        [nil, @readyz[$1] ? 0 : 1]
      when /get endpointslices/
        [{ 'items' => [{ 'endpoints' => @endpoints }] }.to_json, 0]
      when /get deployments/
        items = @deployments.map do |name, ready|
          { 'metadata' => { 'name' => name }, 'status' => ready ? { 'readyReplicas' => ready } : {} }
        end
        [{ 'items' => items }.to_json, 0]
      else
        ['', 0]
      end
    end
  end

  def setup
    @config = mock_config
    @config.logger.level = Logger::WARN
    @bootstrap = Porkadot::Install::Bootstrap.new(@config)
    @cluster = FakeCluster.new

    # Fake clock: each pause advances time by the poll interval.
    clock = [0]
    @bootstrap.define_singleton_method(:now) { clock[0] }
    @bootstrap.define_singleton_method(:pause) { clock[0] += Porkadot::Install::Bootstrap::POLL_INTERVAL }

    @original_backend = SSHKit.config.backend
    @original_output = SSHKit.config.output
    SSHKit.config.backend = RecordingBackend
    SSHKit.config.output = SSHKit::Formatter::BlackHole.new($stdout)
    RecordingBackend.commands = []
    RecordingBackend.responder = @cluster.method(:call)
  end

  def teardown
    SSHKit.config.backend = @original_backend
    SSHKit.config.output = @original_output
  end

  def commands
    RecordingBackend.commands
  end

  def cleanup_index
    commands.index { |c| c.include?('cleanup.sh') }
  end

  def test_cleanup_waits_for_readyz_of_every_master
    @bootstrap.cleanup

    MASTERS.each do |m|
      assert commands.any? { |c| c.include?("curl -skf https://#{m}:6443/readyz") }, "readyz of #{m} was not checked"
    end
    refute commands.any? { |c| c.include?('/healthz') }
  end

  def test_cleanup_runs_cleanup_sh_after_apiserver_endpoints_and_controllers_are_ready
    @bootstrap.cleanup

    assert cleanup_index, 'cleanup.sh was not executed'
    slices = commands.index { |c| c.include?('get endpointslices') }
    deployments = commands.index { |c| c.include?('get deployments') }
    assert slices && slices < cleanup_index
    assert deployments && deployments < cleanup_index
  end

  def test_cleanup_queries_porkadot_kubernetes_endpointslices_through_bootstrap_apiserver
    @bootstrap.cleanup

    query = commands.find { |c| c.include?('get endpointslices') }
    assert_includes query, '/opt/bin/kubectl'
    assert_includes query, '--server https://127.0.0.1:6443'
    assert_includes query, '-n kube-system'
    assert_includes query, '-l kubernetes.io/service-name=porkadot-kubernetes'
    assert_includes query, 'kube_temp/bootstrap/bootstrap/secrets/kubernetes/admin.crt'
  end

  def test_cleanup_keeps_waiting_until_master_endpoints_become_ready
    @cluster.endpoints = MASTERS.map { |m| @cluster.endpoint(m, false) }
    polls = 0
    RecordingBackend.responder = lambda do |cmd|
      if cmd.include?('get endpointslices')
        polls += 1
        @cluster.endpoints = MASTERS.map { |m| @cluster.endpoint(m, true) } if polls == 3
      end
      @cluster.call(cmd)
    end

    @bootstrap.cleanup

    assert_equal 3, polls
    assert cleanup_index
  end

  def test_cleanup_fails_without_removing_bootstrap_when_endpoints_never_become_ready
    @cluster.endpoints = [
      @cluster.endpoint('192.168.33.111', true),
      @cluster.endpoint('192.168.33.112', false),
      @cluster.bootstrap_endpoint('node01', true),
    ]

    error = assert_raises(Porkadot::Error) { @bootstrap.cleanup(timeout: 60) }

    assert_nil cleanup_index, 'cleanup.sh must not run on timeout'
    assert_match(/not ready.*: 192\.168\.33\.112, 192\.168\.33\.113$/, error.message)
    assert_match(/porkadot-kubernetes/, error.message)
    assert_match(/kubectl/, error.message)
  end

  def test_cleanup_fails_when_master_readyz_never_succeeds
    @cluster.readyz['192.168.33.113'] = false

    error = assert_raises(Porkadot::Error) { @bootstrap.cleanup(timeout: 60) }

    assert_nil cleanup_index
    assert_match(%r{https://192\.168\.33\.113:6443/readyz}, error.message)
  end

  def test_cleanup_fails_when_controller_manager_has_no_ready_replica
    @cluster.deployments['kube-controller-manager'] = nil

    error = assert_raises(Porkadot::Error) { @bootstrap.cleanup(timeout: 60) }

    assert_nil cleanup_index
    assert_match(/no ready replica: kube-controller-manager$/, error.message)
  end

  def test_cleanup_timeout_prints_nothing_to_stderr
    @cluster.readyz['192.168.33.113'] = false

    _, err = capture_io do
      assert_raises(Porkadot::Error) { @bootstrap.cleanup(timeout: 60) }
    end

    assert_empty err, 'the error should be reported once, by the caller'
  end

  def test_cleanup_reports_when_vip_does_not_answer_after_cleanup
    @cluster.vip_after_cleanup = false

    error = assert_raises(Porkadot::Error) { @bootstrap.cleanup(timeout: 60) }

    assert cleanup_index, 'cleanup.sh should have run before the post check'
    assert_match(/192\.168\.33\.101:6443/, error.message)
    assert_match(/install bootstrap node/, error.message)
  end

  # --- unready_apiservers ---

  def test_unready_apiservers_ignores_bootstrap_apiserver_endpoint
    slices = { 'items' => [{ 'endpoints' => [@cluster.bootstrap_endpoint('192.168.33.111', true)] }] }

    assert_equal ['192.168.33.111'], @bootstrap.unready_apiservers(slices, ['192.168.33.111'])
  end

  def test_unready_apiservers_treats_missing_ready_condition_as_ready
    slices = { 'items' => [{ 'endpoints' => [@cluster.endpoint('192.168.33.111', nil)] }] }

    assert_equal [], @bootstrap.unready_apiservers(slices, ['192.168.33.111'])
  end

  def test_unready_apiservers_looks_at_every_slice
    slices = { 'items' => [
      { 'endpoints' => [@cluster.endpoint('192.168.33.111', true)] },
      { 'endpoints' => nil },
      { 'endpoints' => [@cluster.endpoint('192.168.33.112', true)] },
    ] }

    assert_equal ['192.168.33.113'], @bootstrap.unready_apiservers(slices, MASTERS)
  end

  # --- CLI ---

  def test_main_prints_porkadot_error_once_without_backtrace
    fake = Object.new
    fake.define_singleton_method(:cleanup) { |timeout: nil| raise Porkadot::Error, "Timed out waiting for X\nBootstrap static Pods were not removed." }

    original_new = Porkadot::Install::Bootstrap.method(:new)
    silence_warnings { Porkadot::Install::Bootstrap.define_singleton_method(:new) { |_| fake } }
    status = nil
    begin
      _, err = capture_io do
        status = Porkadot::Cmd::Cli.main(['install', 'bootstrap', 'cleanup',
          '--config', File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml')])
      end
    ensure
      silence_warnings { Porkadot::Install::Bootstrap.define_singleton_method(:new) { |*args| original_new.call(*args) } }
    end

    assert_equal 1, status
    assert_equal "Timed out waiting for X\nBootstrap static Pods were not removed.\n", err
  end

  def test_main_returns_zero_on_success
    fake = Object.new
    fake.define_singleton_method(:cleanup) { |timeout: nil| nil }

    original_new = Porkadot::Install::Bootstrap.method(:new)
    silence_warnings { Porkadot::Install::Bootstrap.define_singleton_method(:new) { |_| fake } }
    status = nil
    begin
      capture_io do
        status = Porkadot::Cmd::Cli.main(['install', 'bootstrap', 'cleanup',
          '--config', File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml')])
      end
    ensure
      silence_warnings { Porkadot::Install::Bootstrap.define_singleton_method(:new) { |*args| original_new.call(*args) } }
    end

    assert_equal 0, status
  end

  def test_cli_passes_timeout_to_cleanup
    calls = []
    fake = Object.new
    fake.define_singleton_method(:cleanup) { |timeout: nil| calls << timeout }

    original_new = Porkadot::Install::Bootstrap.method(:new)
    silence_warnings { Porkadot::Install::Bootstrap.define_singleton_method(:new) { |_| fake } }
    begin
      run_cli('install', 'bootstrap', 'cleanup', '--timeout', '120',
              '--config', File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml'))
    ensure
      silence_warnings { Porkadot::Install::Bootstrap.define_singleton_method(:new) { |*args| original_new.call(*args) } }
    end

    assert_equal [120], calls
  end

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
