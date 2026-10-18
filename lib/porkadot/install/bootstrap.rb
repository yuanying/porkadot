module Porkadot; module Install
  class Bootstrap
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'bootstrap')
    # Used by porkadot before secrets were merged into the assets tree.
    LEGACY_SECRETS_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.bootstrap')
    # Client credentials uploaded by cleanup, used to query the bootstrap apiserver.
    BOOTSTRAP_SECRETS_TEMP = File.join(KUBE_TEMP, 'bootstrap', 'secrets', 'kubernetes')
    # Service behind the control plane endpoint (VIP).
    APISERVER_SERVICE = 'porkadot-kubernetes'
    BOOTSTRAP_APISERVER_POD_PREFIX = 'bootstrap-kube-apiserver'
    CONTROLLER_DEPLOYMENTS = ['kube-controller-manager', 'kube-scheduler']
    DEFAULT_CLEANUP_TIMEOUT = 600
    POLL_INTERVAL = 5
    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger
    attr_reader :host

    def initialize global_config
      @global_config = global_config
      @config = global_config.bootstrap
      @logger = global_config.logger
      @host = Porkadot::Install::Kubelet.new(self.config.kubelet_config)
    end

    def install
      global_config = self.global_config
      config = self.config
      uploader = Porkadot::Install::Uploader.new(global_config)
      on(host) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        execute(:rm, '-rf', KUBE_TEMP, LEGACY_SECRETS_TEMP)
        uploader.upload_tree(self, config.target_path, KUBE_TEMP)

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'install.sh'))
        end

       endpoint = "https://127.0.0.1:#{global_config.k8s.apiserver.bind_port}/readyz"
       info "Start to wait for Bootstrapping Kubernetes API: #{endpoint}"
        while !test('curl', '-skf', endpoint)
          info "Still wating for Bootstrapping Kubernetes API..."
          sleep 5
        end
      end
    end

    # Removes the bootstrap static Pods once the self-hosted control plane can
    # take over. Until then the bootstrap apiserver is the only one behind the
    # VIP, so removing it early leaves kubelets and kube-proxy without an API.
    # Raises Porkadot::Error without removing anything if the wait times out.
    def cleanup timeout: DEFAULT_CLEANUP_TIMEOUT
      config = self.config
      bootstrap = self
      uploader = Porkadot::Install::Uploader.new(global_config)
      # Sequential: the parallel runner's thread would print the error and its
      # backtrace again when it dies.
      on(host, in: :sequence) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        execute(:rm, '-rf', KUBE_TEMP, LEGACY_SECRETS_TEMP)
        uploader.upload_tree(self, config.target_path, KUBE_TEMP)

        bootstrap.wait_for_handover(self, timeout)

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'cleanup.sh'))
        end

        bootstrap.wait_for_vip_after_cleanup(self, timeout)
      end
    rescue SSHKit::Runner::ExecuteError => e
      raise e.cause if e.cause.is_a?(Porkadot::Error)
      raise
    end

    def wait_for_handover backend, timeout
      deadline = now + timeout
      port = global_config.k8s.apiserver.bind_port
      masters = apiserver_node_names

      masters.each do |name|
        endpoint = "https://#{name}:#{port}/readyz"
        wait_until(backend, deadline, "API node #{name}", <<~HINT) do
          #{endpoint} did not answer. Check the kube-apiserver Pod on #{name}
          (crictl ps --name kube-apiserver on the node, or kubectl -n kube-system get pods -o wide).
        HINT
          backend.test(:curl, '-skf', endpoint) ? nil : endpoint
        end
      end

      wait_until(backend, deadline, "apiserver endpoints of #{APISERVER_SERVICE}", <<~HINT) do
        Check the EndpointSlice through the bootstrap apiserver:
          kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=#{APISERVER_SERVICE} -o yaml
        Every master's kube-apiserver Pod must be Ready (kubectl -n kube-system get pods -o wide).
      HINT
        slices = kubectl_json(backend, 'get', 'endpointslices', '-l', "kubernetes.io/service-name=#{APISERVER_SERVICE}")
        unready = slices ? unready_apiservers(slices, masters) : masters
        unready.empty? ? nil : "not ready in EndpointSlice of kube-system/#{APISERVER_SERVICE}: #{unready.join(', ')}"
      end

      wait_until(backend, deadline, CONTROLLER_DEPLOYMENTS.join(' and '), <<~HINT) do
        Check the Deployments: kubectl -n kube-system get deployments #{CONTROLLER_DEPLOYMENTS.join(' ')}
      HINT
        deployments = kubectl_json(backend, 'get', 'deployments', *CONTROLLER_DEPLOYMENTS)
        unready = deployments ? unready_deployments(deployments) : CONTROLLER_DEPLOYMENTS
        unready.empty? ? nil : "no ready replica: #{unready.join(', ')}"
      end
    end

    def wait_for_vip_after_cleanup backend, timeout
      deadline = now + timeout
      endpoint = "https://#{global_config.k8s.control_plane_endpoint}/readyz"
      wait_until(backend, deadline, "API endpoint after cleanup", <<~HINT, action: 'Bootstrap static Pods were already removed.') do
        To recover, run `porkadot install bootstrap node` again, wait until
        kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=#{APISERVER_SERVICE}
        shows every master as ready, then run `porkadot install bootstrap cleanup` again.
      HINT
        backend.test(:curl, '-skf', endpoint) ? nil : endpoint
      end
    end

    # Masters (by node name) without a ready kube-apiserver endpoint.
    # The bootstrap apiserver is selected by the same Service, but it does not count.
    def unready_apiservers slices, masters
      ready = (slices['items'] || []).flat_map { |slice| slice['endpoints'] || [] }.select do |ep|
        pod = (ep['targetRef'] || {})['name'].to_s
        # A missing ready condition means ready (discovery.k8s.io/v1).
        ready = (ep['conditions'] || {})['ready']
        !pod.start_with?(BOOTSTRAP_APISERVER_POD_PREFIX) && ready != false
      end.map { |ep| ep['nodeName'] }
      masters - ready
    end

    def unready_deployments deployments
      ready = (deployments['items'] || []).select do |d|
        (d.dig('status', 'readyReplicas') || 0) > 0
      end.map { |d| d.dig('metadata', 'name') }
      CONTROLLER_DEPLOYMENTS - ready
    end

    def apiserver_node_names
      global_config.nodes.values.select(&:apiserver?).map(&:hostname)
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def pause
      sleep POLL_INTERVAL
    end

    private

    # Polls the block until it returns nil. A non-nil value describes what is
    # still missing and is reported when the deadline passes.
    def wait_until backend, deadline, subject, hint, action: 'Bootstrap static Pods were not removed.'
      backend.info "Start to wait for #{subject}"
      loop do
        pending = yield
        return if pending.nil?
        if now >= deadline
          raise Porkadot::Error, "Timed out waiting for #{subject}: #{pending}\n#{action}\n#{hint}"
        end
        backend.info "Still waiting for #{subject}: #{pending}"
        pause
      end
    end

    # Queries the bootstrap apiserver directly, not through the VIP.
    def kubectl_json backend, *args
      out = backend.capture(:'/opt/bin/kubectl',
        '--server', "https://127.0.0.1:#{global_config.k8s.apiserver.bind_port}",
        '--certificate-authority', File.join(BOOTSTRAP_SECRETS_TEMP, 'ca.crt'),
        '--client-certificate', File.join(BOOTSTRAP_SECRETS_TEMP, 'admin.crt'),
        '--client-key', File.join(BOOTSTRAP_SECRETS_TEMP, 'admin.key'),
        '-n', 'kube-system', *args, '-o', 'json',
        raise_on_non_zero_exit: false)
      JSON.parse(out)
    rescue JSON::ParserError
      nil
    end

  end

end; end
