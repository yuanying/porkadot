require 'open3'
require 'json'
require 'yaml'

module Porkadot
  # Thin wrapper around the sops command. Contents are passed through
  # stdin/stdout so that plain secrets are never written to disk.
  #
  # Secrets are always encrypted in sops' binary format: the output is a JSON
  # document whose top-level `sops` key marks it as encrypted, and decryption
  # gives back exactly the original bytes. (sops' YAML format rewrites YAML on
  # the way back, e.g. drops a leading `---`.)
  class Sops
    attr_reader :cwd
    attr_reader :config_path
    attr_reader :command

    # cwd is where sops looks up .sops.yaml unless config_path is given.
    def initialize cwd:, config_path: nil, command: 'sops'
      @cwd = cwd
      @config_path = config_path
      @command = command
    end

    # Whether content is a sops-encrypted YAML or JSON document.
    def self.encrypted? content
      content = content.to_s
      return false unless content.include?('sops')
      doc = YAML.safe_load(content, permitted_classes: [Time, Date, Symbol], aliases: true)
      doc.is_a?(Hash) && doc.key?('sops')
    rescue Psych::Exception, ArgumentError
      false
    end

    # path is the asset path; sops uses it to pick a creation rule.
    def encrypt content, path:
      self.run('encrypt', '--input-type', 'binary', '--output-type', 'json', content, path)
    end

    def decrypt content, path:
      type = self.json?(content) ? %w(--input-type json --output-type binary) : %w(--input-type yaml --output-type yaml)
      self.run('decrypt', *type, content, path)
    end

    protected

    def json? content
      JSON.parse(content)
      true
    rescue JSON::ParserError
      false
    end

    def run subcommand, *args, content, path
      cmd = [self.command]
      cmd += ['--config', self.config_path] if self.config_path
      cmd += [subcommand, *args, '--filename-override', File.expand_path(path)]
      out, err, status = Open3.capture3(*cmd, stdin_data: content.to_s.b, chdir: self.cwd, binmode: true)
      unless status.success?
        raise Porkadot::Error, "sops #{subcommand} failed for #{path}: #{err.strip}"
      end
      out
    rescue Errno::ENOENT
      raise Porkadot::Error, "sops command not found: #{self.command}"
    end
  end
end
