require 'open3'

# Creates a throwaway age key and .sops.yaml for tests that run the real
# sops binary. Tests are skipped only when sops or age-keygen is missing.
module Porkadot::SopsTestUtils
  def sops_available?
    %w(sops age-keygen).all? { |cmd| system("command -v #{cmd} >/dev/null 2>&1") }
  end

  def setup_sops dir
    skip 'sops and age-keygen are required' unless sops_available?
    key_file = File.join(dir, 'age.key')
    _, err, status = Open3.capture3('age-keygen', '-o', key_file)
    raise "age-keygen failed: #{err}" unless status.success?
    recipient = File.read(key_file)[/public key: (\S+)/, 1]
    File.write(File.join(dir, '.sops.yaml'), <<~YAML)
      creation_rules:
        - path_regex: assets/.*
          age: #{recipient}
    YAML
    @saved_sops_age_key_file = ENV['SOPS_AGE_KEY_FILE']
    ENV['SOPS_AGE_KEY_FILE'] = key_file
  end

  def teardown_sops
    ENV['SOPS_AGE_KEY_FILE'] = @saved_sops_age_key_file
  end

  def sops_encrypted_file? path
    Porkadot::Sops.encrypted?(File.binread(path))
  end
end
