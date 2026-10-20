require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class PorkadotAssetsInstallDepsTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @tmpdir = Dir.mktmpdir
    @opt_dir = File.join(@tmpdir, 'opt')
    @stub_dir = File.join(@tmpdir, 'stub')
    @log = File.join(@tmpdir, 'curl.log')
    FileUtils.mkdir_p(@stub_dir)
    write_curl_stub
    render_script
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_fresh_node_downloads_everything_and_links_target_versions
    assert run_script.success?, @output

    assert_links_to_targets
    assert_equal "kubelet #{k8s_version}", File.read(bin('kubelet'))
    assert_equal "etcdctl #{etcd_version}", File.read(bin('etcdctl'))
    assert_equal "etcdutl #{etcd_version}", File.read(bin('etcdutl'))
    assert_equal "crictl #{crictl_version}", File.read(bin('crictl'))
    assert File.executable?(bin("kubelet-#{k8s_version}"))
    assert_equal "bridge #{cni_version}", File.read(File.join(@opt_dir, 'cni', 'bin', 'bridge'))
    assert_equal cni_version, File.read(cni_marker).strip
    assert_equal 6, downloads.size
  end

  def test_up_to_date_node_downloads_nothing
    assert run_script.success?, @output
    assert run_script.success?, @output

    assert_empty downloads
    assert_links_to_targets
  end

  def test_rollback_relinks_versions_left_on_node_without_downloading
    # The node was upgraded and now runs other versions, while the target
    # versions are still on disk from before.
    assert run_script.success?, @output
    %w(kubectl kubelet).each { |name| install_other(name, 'v9.99.0') }
    install_other('etcdctl', '9.99.0')
    install_other('etcdutl', '9.99.0')
    install_other('crictl', 'v9.99.0')

    assert run_script.success?, @output

    assert_links_to_targets
    assert_empty downloads
  end

  def test_relinks_when_only_etcd_version_differs
    assert run_script.success?, @output
    install_other('etcdctl', '9.99.0')
    FileUtils.rm_f(bin("etcdctl-#{etcd_version}"))

    assert run_script.success?, @output

    assert_links_to_targets
    assert_equal ["etcd-v#{etcd_version}-linux"], downloads.map { |url| File.basename(url)[/etcd-v[^-]+-linux/] }
  end

  def test_regular_file_in_place_of_link_is_replaced
    assert run_script.success?, @output
    FileUtils.rm_f(bin('crictl'))
    File.write(bin('crictl'), 'unmanaged')

    assert run_script.success?, @output

    assert_links_to_targets
  end

  def test_cni_plugins_are_extracted_when_marker_differs
    assert run_script.success?, @output
    File.write(cni_marker, "v0.8.0\n")

    assert run_script.success?, @output

    assert_equal 1, downloads.size
    assert_includes downloads.first, "cni-plugins-linux-"
    assert_equal cni_version, File.read(cni_marker).strip
  end

  def test_cni_plugins_are_extracted_when_marker_is_missing
    # Nodes installed by earlier porkadot have no marker.
    assert run_script.success?, @output
    FileUtils.rm_f(cni_marker)

    assert run_script.success?, @output

    assert_equal 1, downloads.size
    assert_equal cni_version, File.read(cni_marker).strip
  end

  def test_force_downloads_everything_again
    assert run_script.success?, @output

    assert run_script('--force').success?, @output

    assert_equal 6, downloads.size
    assert_links_to_targets
  end

  def test_failed_download_leaves_no_versioned_binary
    status = run_script(fail: 'kubelet')

    refute status.success?, @output
    refute File.exist?(bin("kubelet-#{k8s_version}"))
    refute File.exist?(bin("kubelet-#{k8s_version}.tmp"))
  end

  def test_unknown_argument_fails
    refute run_script('--forse').success?, @output
    assert_empty downloads
  end

  private

  def render_script
    config_path = write_tmp_config(@tmpdir)
    @config = Porkadot::Config.new(config_path)
    @config.logger.level = Logger::WARN
    kubelet_default = Porkadot::Assets::KubeletDefault.new(@config.kubelet_default)
    kubelet_default.render_erb 'install-deps.sh'
    @script = kubelet_default.config.asset_path('install-deps.sh')
  end

  # Fakes the release downloads: binaries contain "<name> <version>", and
  # archives have the same layout as the upstream releases.
  def write_curl_stub
    path = File.join(@stub_dir, 'curl')
    File.write(path, <<~'SH')
      #!/bin/bash
      set -eu
      out=""
      url=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -o) out="$2"; shift 2 ;;
          -*) shift ;;
          *) url="$1"; shift ;;
        esac
      done
      echo "${url}" >> "${STUB_LOG}"
      if [ -n "${STUB_FAIL:-}" ] && [[ "${url}" == *"/${STUB_FAIL}"* ]]; then
        echo partial > "${out}"
        exit 22
      fi
      work=$(mktemp -d)
      case "${url}" in
        */cni-plugins-linux-*)
          ver=$(basename "${url}" | sed -E 's/.*-(v[^-]+)\.tgz$/\1/')
          echo -n "bridge ${ver}" > "${work}/bridge"
          tar -C "${work}" -czf "${out}" bridge ;;
        */etcd-v*)
          ver=$(basename "${url}" | sed -E 's/^etcd-v([^-]+)-.*/\1/')
          mkdir "${work}/etcd"
          echo -n "etcdctl ${ver}" > "${work}/etcd/etcdctl"
          echo -n "etcdutl ${ver}" > "${work}/etcd/etcdutl"
          tar -C "${work}" -czf "${out}" etcd ;;
        */crictl-*)
          ver=$(basename "${url}" | sed -E 's/^crictl-(v[^-]+)-.*/\1/')
          echo -n "crictl ${ver}" > "${work}/crictl"
          tar -C "${work}" -czf "${out}" crictl ;;
        */bin/linux/*)
          ver=$(echo "${url}" | sed -E 's#.*/(v[^/]+)/bin/.*#\1#')
          echo -n "$(basename "${url}") ${ver}" > "${out}" ;;
        *) exit 1 ;;
      esac
      rm -rf "${work}"
    SH
    File.chmod(0755, path)
  end

  def run_script *args, fail: nil
    File.write(@log, '')
    env = {
      'PATH' => "#{@stub_dir}:#{ENV['PATH']}",
      'STUB_LOG' => @log,
      'STUB_FAIL' => fail.to_s,
      'PORKADOT_OPT_DIR' => @opt_dir,
    }
    @output, status = Open3.capture2e(env, 'bash', @script, *args)
    status
  end

  # Target versions, as rendered into the script.
  def k8s_version
    @config.k8s.kubernetes_version
  end

  def etcd_version
    @config.etcd.image_tag.gsub(/\-\w+$/, '')
  end

  def crictl_version
    @config.k8s.crictl_version
  end

  def cni_version
    @config.k8s.networking.cni_version
  end

  def bin name
    File.join(@opt_dir, 'bin', name)
  end

  def cni_marker
    File.join(@opt_dir, 'cni', 'bin', '.porkadot-cni-plugins-version')
  end

  def downloads
    File.read(@log).lines.map(&:strip).reject(&:empty?)
  end

  def install_other name, version
    path = bin("#{name}-#{version}")
    File.write(path, "#{name} #{version}")
    FileUtils.rm_f(bin(name))
    File.symlink(path, bin(name))
  end

  def assert_links_to_targets
    { 'kubectl' => k8s_version, 'kubelet' => k8s_version, 'etcdctl' => etcd_version, 'etcdutl' => etcd_version, 'crictl' => crictl_version }.each do |name, version|
      assert File.symlink?(bin(name)), "#{name} is not a symlink"
      assert_equal bin("#{name}-#{version}"), File.readlink(bin(name))
    end
  end
end
