require "test_helper"
require "sops_helper"
require "json"

class PorkadotSopsTest < Minitest::Test
  include Porkadot::TestUtils
  include Porkadot::SopsTestUtils

  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    teardown_sops
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_encrypted_detects_top_level_sops_key
    assert Porkadot::Sops.encrypted?(JSON.dump('data' => 'ENC[...]', 'sops' => { 'version' => '3.13.3' }))
    assert Porkadot::Sops.encrypted?("apiVersion: ENC[...]\nsops:\n  version: 3.13.3\n")
  end

  def test_encrypted_is_false_for_plain_files
    refute Porkadot::Sops.encrypted?("-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----\n")
    refute Porkadot::Sops.encrypted?("#!/bin/bash\nset -eu\necho sops: done\n")
    refute Porkadot::Sops.encrypted?("---\napiVersion: v1\nkind: Secret\ndata:\n  sops: x\n")
    refute Porkadot::Sops.encrypted?("key: [unclosed\nsops: {")
    refute Porkadot::Sops.encrypted?("")
  end

  def test_round_trip_with_real_sops_keeps_bytes
    setup_sops(@tmpdir)
    sops = Porkadot::Sops.new(cwd: @tmpdir)
    path = File.join(@tmpdir, 'assets', 'kubernetes', 'kubeconfig.yaml')
    plain = "---\napiVersion: v1\nclusters:\n- cluster:\n    server: https://127.0.0.1\n  name: x\n"

    encrypted = sops.encrypt(plain, path: path)

    assert Porkadot::Sops.encrypted?(encrypted)
    refute_includes encrypted, 'https://127.0.0.1'
    assert JSON.parse(encrypted).key?('data'), 'secrets are encrypted in sops binary format'
    assert_equal plain.b, sops.decrypt(encrypted, path: path).b
  end

  def test_explicit_config_path
    setup_sops(@tmpdir)
    elsewhere = File.join(@tmpdir, 'elsewhere')
    FileUtils.mkdir_p(elsewhere)
    sops = Porkadot::Sops.new(cwd: elsewhere, config_path: File.join(@tmpdir, '.sops.yaml'))

    encrypted = sops.encrypt("secret\n", path: File.join(@tmpdir, 'assets', 'a.key'))

    assert Porkadot::Sops.encrypted?(encrypted)
  end

  def test_failure_raises_porkadot_error
    setup_sops(@tmpdir)
    sops = Porkadot::Sops.new(cwd: @tmpdir)

    error = assert_raises(Porkadot::Error) do
      sops.encrypt("secret\n", path: File.join(@tmpdir, 'no-rule', 'a.key'))
    end
    assert_match(/sops/, error.message)
  end
end
