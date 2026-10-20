require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

# Runs the rendered kubernetes/install.sh with a fake kubectl.
class PorkadotAssetsKubernetesInstallTest < Minitest::Test
  include Porkadot::TestUtils

  def setup
    @tmpdir = Dir.mktmpdir
    @stub_dir = File.join(@tmpdir, 'stub')
    @log = File.join(@tmpdir, 'kubectl.log')
    FileUtils.mkdir_p(@stub_dir)
    write_stubs
    config_path = copy_rendered_kubernetes(@tmpdir)
    @script = File.join(@tmpdir, 'assets', 'kubernetes', 'install.sh')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  # The kube-apiserver goes first and every apiserver must run the new
  # version before the controller-manager and the scheduler are replaced:
  # a newer scheduler can wait forever for APIs an older apiserver lacks,
  # and then nothing schedules the new apiserver Pods.
  def test_apiserver_is_rolled_out_before_the_rest
    assert run_script.success?, @output

    apply_apiserver = calls.index { |c| c.start_with?('apply') && c.include?('-l=app.kubernetes.io/component=kube-apiserver') }
    rollout = calls.index { |c| c.start_with?('-n kube-system rollout status daemonset/kube-apiserver') }
    apply_all = calls.index { |c| c.start_with?('apply') && c.include?('--prune ') }
    crds = calls.index { |c| c.include?('manifests/crds') }

    assert apply_apiserver, calls.inspect
    assert rollout, calls.inspect
    assert apply_all, calls.inspect
    assert crds < apply_apiserver, calls.inspect
    assert apply_apiserver < rollout, calls.inspect
    assert rollout < apply_all, calls.inspect
    refute_includes calls[apply_apiserver], '--prune'
  end

  def test_waits_until_the_rollout_finishes
    assert run_script(rolled_out_after: 3).success?, @output

    assert_equal 3, calls.count { |c| c.include?('rollout status daemonset/kube-apiserver') }
    assert calls.any? { |c| c.include?('--prune ') }, calls.inspect
  end

  # The apiservers restart during the rollout, so a failed request does not
  # end the wait.
  def test_failed_status_requests_do_not_end_the_wait
    assert run_script(rolled_out_after: 2, status_fails: true).success?, @output

    assert calls.any? { |c| c.include?('--prune ') }, calls.inspect
  end

  def test_timeout_stops_before_the_rest_is_applied
    status = run_script(rolled_out_after: 1000, timeout: 0)

    refute status.success?, @output
    assert_match(/kube-apiserver/, @output)
    assert_match(/did not finish/, @output)
    refute calls.any? { |c| c.include?('--prune ') }, calls.inspect
  end

  # A new cluster is installed through the bootstrap apiserver; its
  # apiservers become ready only once everything else is in place.
  def test_no_wait_applies_everything_at_once
    assert run_script(env: { 'KUBE_WAIT_APISERVER' => 'false' }).success?, @output

    refute calls.any? { |c| c.include?('rollout status') }, calls.inspect
    assert_equal 1, calls.count { |c| c.start_with?('apply') && c.include?('-k ') }
    assert calls.any? { |c| c.include?('--prune ') }, calls.inspect
  end

  def test_single_target_is_applied_alone
    assert run_script(env: { 'KUBE_TARGET' => 'kube-scheduler' }).success?, @output

    applies = calls.select { |c| c.start_with?('apply') }
    assert_equal 1, applies.size, calls.inspect
    assert_includes applies.first, '-l=app.kubernetes.io/component=kube-scheduler'
    refute calls.any? { |c| c.include?('rollout status') }, calls.inspect
  end

  private

  # kubectl logs its arguments. `rollout status --watch=false` reports the
  # DaemonSet as rolled out from the ROLLED_OUT_AFTER-th call.
  def write_stubs
    kubectl = File.join(@stub_dir, 'kubectl')
    File.write(kubectl, <<~'SH')
      #!/bin/bash
      echo "$*" >> "${STUB_LOG}"
      case "$*" in
        *"rollout status"*)
          n=$(grep -c 'rollout status' "${STUB_LOG}")
          if [ "${n}" -ge "${ROLLED_OUT_AFTER}" ]; then
            echo 'daemon set "kube-apiserver" successfully rolled out'
          elif [ "${STATUS_FAILS}" = true ]; then
            echo 'The connection to the server was refused' >&2
            exit 1
          else
            echo 'Waiting for daemon set "kube-apiserver" rollout to finish: 1 out of 3 new pods have been updated...'
          fi ;;
      esac
      exit 0
    SH
    File.chmod(0755, kubectl)
    sleep = File.join(@stub_dir, 'sleep')
    File.write(sleep, "#!/bin/bash\nexit 0\n")
    File.chmod(0755, sleep)
  end

  def run_script rolled_out_after: 1, status_fails: false, timeout: 600, env: {}
    File.write(@log, '')
    script = File.read(@script).gsub('/opt/bin/kubectl', File.join(@stub_dir, 'kubectl'))
    path = File.join(@tmpdir, 'assets', 'kubernetes', 'install.test.sh')
    File.write(path, script)
    env = {
      'PATH' => "#{@stub_dir}:#{ENV['PATH']}",
      'STUB_LOG' => @log,
      'ROLLED_OUT_AFTER' => rolled_out_after.to_s,
      'STATUS_FAILS' => status_fails.to_s,
      'KUBE_APISERVER_TIMEOUT' => timeout.to_s,
    }.merge(env)
    @output, status = Open3.capture2e(env, 'bash', path)
    status
  end

  def calls
    File.read(@log).lines.map(&:strip).reject(&:empty?)
  end
end
