require 'logger'
require 'stringio'
require 'net/ssh'

module Porkadot; module Install
  # Raised when porkadot cannot connect or log in to a node. The message is
  # written for the user: the node, what failed and what to check.
  class SshError < Porkadot::Error
    CONNECT_ERRORS = [
      Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
      Errno::ETIMEDOUT, SocketError, Net::SSH::ConnectionTimeout,
    ]
    ERRORS = [Net::SSH::Exception, *CONNECT_ERRORS]

    def self.build host, error, log
      target = "#{host.user ? "#{host.user}@" : ''}#{host.hostname}:#{host.port || 22}"
      cause = "#{error.class}: #{error.message}"
      case error
      when Net::SSH::HostKeyMismatch
        new("Host key of #{target} does not match known_hosts (#{cause})\n" \
          "Compare `ssh-keygen -F #{host.hostname}` with `ssh-keyscan #{host.hostname}`.")
      when Net::SSH::HostKeyUnknown
        new("Host key of #{target} is not in known_hosts (#{cause})\n" \
          "Connect once with `ssh #{host.hostname}` to add it.")
      when Net::SSH::AuthenticationFailed
        lines = ["SSH authentication failed for #{target} (#{cause})", "  ssh-agent: #{agent_status}"]
        keys = host.keys.any? ? host.keys.join(', ') : 'net-ssh defaults and IdentityFile in ~/.ssh/config'
        lines << "  keys: #{keys}"
        lines += log.map { |l| "  net-ssh: #{l}" }
        new(lines.join("\n"))
      when *CONNECT_ERRORS
        new("Cannot connect to #{target}: #{cause}")
      else
        new("SSH to #{target} failed: #{cause}")
      end
    end

    def self.agent_status
      return 'SSH_AUTH_SOCK is not set' unless ENV['SSH_AUTH_SOCK']
      Net::SSH::Authentication::Agent.connect.close
      "available (#{ENV['SSH_AUTH_SOCK']})"
    rescue Net::SSH::Authentication::AgentNotAvailable, Net::SSH::Authentication::AgentError, SystemCallError => e
      "not available at #{ENV['SSH_AUTH_SOCK']} (#{e.message})"
    end
  end

  # SSHKit backend for porkadot. Keeps net-ssh's error log per node, which
  # says why a key could not be loaded, and turns connection and
  # authentication failures into SshError.
  class Netssh < SSHKit::Backend::Netssh
    class Log < ::Logger
      def initialize
        @io = StringIO.new
        super(@io)
        self.formatter = proc { |_severity, _time, _progname, msg| "#{msg}\n" }
      end

      def lines
        @io.string.lines.map(&:chomp)
      end
    end

    # SSHKit keeps the connection pool and the ssh_options on the class.
    class << self
      def pool
        SSHKit::Backend::Netssh.pool
      end

      def config
        SSHKit::Backend::Netssh.config
      end
    end

    private

    def with_ssh(&block)
      options = host.ssh_options || {}
      unless options[:logger]
        # verbose overrides LogLevel in ~/.ssh/config, which only sets how
        # much net-ssh writes to this log.
        host.ssh_options = { logger: Log.new, verbose: :error }.merge(options)
      end
      super
    rescue *SshError::ERRORS => e
      log = host.ssh_options[:logger]
      raise SshError.build(host, e, log.respond_to?(:lines) ? log.lines : [])
    end
  end
end; end

SSHKit.config.backend = Porkadot::Install::Netssh
