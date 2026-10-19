require 'test_helper'
require 'tmpdir'

class PorkadotInstallSshTest < Minitest::Test
  include Porkadot::TestUtils

  HOST = '192.0.2.10'

  def kubelet name, raw={}
    raw = ::Porkadot::Raw.new(raw)
    config = Porkadot::Configs::Kubelet.new(self.mock_config, name, raw)
    return Porkadot::Install::Kubelet.new(config)
  end

  # --- known_hosts ---

  def test_known_hosts_returns_every_key_of_a_hashed_host
    rsa = OpenSSL::PKey::RSA.new(2048)
    ecdsa = OpenSSL::PKey::EC.generate('prime256v1')
    keys = with_known_hosts([hashed_line(HOST, rsa), hashed_line(HOST, ecdsa)]) do |options|
      known_hosts.search_for(HOST, options)
    end

    assert_equal ['ssh-rsa', 'ecdsa-sha2-nistp256'], keys.map(&:ssh_type)
    assert keys.any? { |k| k.to_blob == ecdsa.to_blob }, 'the ecdsa key the server offers should be known'
  end

  def test_known_hosts_reads_ed25519_lines
    blob = Net::SSH::Buffer.from(:string, 'ssh-ed25519', :string, "\x01" * 32).to_s
    line = "#{hashed_host(HOST)} ssh-ed25519 #{[blob].pack('m0')}"
    keys = with_known_hosts([line]) do |options|
      known_hosts.search_for(HOST, options)
    end

    assert_equal ['ssh-ed25519'], keys.map(&:ssh_type)
  end

  # --- keys ---

  def test_keys_are_left_to_net_ssh_by_default
    refute kubelet('test', { hostname: HOST }).netssh_options.key?(:keys)
  end

  def test_keys_in_connection_are_passed_to_net_ssh
    k = kubelet('test', { hostname: HOST, connection: { keys: ['~/.ssh/id_rsa'] } })
    assert_equal ['~/.ssh/id_rsa'], k.netssh_options[:keys]
  end

  # --- errors ---

  def test_authentication_failure_shows_keys_that_could_not_be_loaded
    error = run_with_ssh_start(env: { 'SSH_AUTH_SOCK' => nil }) do |_host, user, options|
      options[:logger].error('net.ssh.authentication.key_manager') do
        "could not load private key file `/home/u/.ssh/id_ed25519': NotImplementedError (unsupported key type `ssh-ed25519')"
      end
      raise Net::SSH::AuthenticationFailed, "Authentication failed for user #{user}@#{HOST}"
    end

    assert_kind_of Porkadot::Error, error
    assert_includes error.message, "ubuntu@#{HOST}:22"
    assert_includes error.message, 'Net::SSH::AuthenticationFailed'
    assert_includes error.message, 'SSH_AUTH_SOCK is not set'
    assert_includes error.message, "could not load private key file `/home/u/.ssh/id_ed25519': NotImplementedError"
  end

  def test_host_key_mismatch_points_at_known_hosts
    error = run_with_ssh_start do |*|
      raise Net::SSH::HostKeyMismatch, "fingerprint SHA256:abc does not match for \"#{HOST}\""
    end

    assert_kind_of Porkadot::Error, error
    assert_includes error.message, "ubuntu@#{HOST}:22"
    assert_includes error.message, 'fingerprint SHA256:abc does not match'
    assert_includes error.message, "ssh-keygen -F #{HOST}"
  end

  def test_connection_failure_is_reported
    error = run_with_ssh_start do |*|
      raise Errno::ECONNREFUSED, "connect(2) for #{HOST}:22"
    end

    assert_kind_of Porkadot::Error, error
    assert_includes error.message, "ubuntu@#{HOST}:22"
    assert_includes error.message, 'Connection refused'
  end

  def test_other_errors_are_not_converted
    error = run_with_ssh_start do |*|
      raise ArgumentError, 'not an ssh error'
    end

    assert_kind_of ArgumentError, error
  end

  def test_main_prints_ssh_error_once_without_backtrace
    status = nil
    _, err = with_ssh_start(->(*_) { raise Errno::ECONNREFUSED, "connect(2) for 192.168.33.111:22" }) do
      capture_subprocess_io do
        status = Porkadot::Cmd::Cli.main(['setup-node', '--node', 'node01',
          '--config', File.join(TEST_FIXTURES_DIR, 'config', 'porkadot.yaml')])
      end
    end

    assert_equal 1, status
    lines = err.lines.reject { |l| l.include?('INFO -- : Setup node default') }
    assert_match(/\ACannot connect to ubuntu@192\.168\.33\.111:22: Errno::ECONNREFUSED/, lines.join)
    refute_match(/\.rb:\d+:in /, err, 'should not print a backtrace')
  end

  private

  def known_hosts
    SSHKit::Backend::Netssh.config.ssh_options[:known_hosts]
  end

  def with_known_hosts lines
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'known_hosts')
      File.write(path, lines.join("\n") + "\n")
      yield user_known_hosts_file: path, global_known_hosts_file: []
    end
  end

  def hashed_host host
    salt = OpenSSL::Random.random_bytes(20)
    hmac = OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha1'), salt, host)
    "|1|#{[salt].pack('m0')}|#{[hmac].pack('m0')}"
  end

  def hashed_line host, key
    "#{hashed_host(host)} #{key.ssh_type} #{[key.to_blob].pack('m0')}"
  end

  # Runs one command on a node through Porkadot's SSHKit backend, with
  # Net::SSH.start replaced by the block. Returns the raised error.
  def run_with_ssh_start env: {}, &start
    host = kubelet(HOST, { connection: { user: 'ubuntu', port: 22 } })
    original_env = env.keys.map { |k| [k, ENV[k]] }.to_h
    env.each { |k, v| ENV[k] = v }
    with_ssh_start(start) do
      Porkadot::Install::Netssh.new(host) { execute(:true) }.run
    end
    flunk 'expected an error'
  rescue Minitest::Assertion
    raise
  rescue => e
    e
  ensure
    original_env&.each { |k, v| ENV[k] = v }
  end

  def with_ssh_start start
    original = Net::SSH.method(:start)
    silence_warnings { Net::SSH.define_singleton_method(:start, &start) }
    yield
  ensure
    silence_warnings { Net::SSH.define_singleton_method(:start, original) }
  end

  def silence_warnings
    verbose, $VERBOSE = $VERBOSE, nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
