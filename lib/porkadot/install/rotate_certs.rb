module Porkadot; module Install
  class RotateCerts
    ETCD_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'rotate-certs-etcd')
    ETCD_SECRETS_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.rotate-certs-etcd')

    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @logger = global_config.logger
    end

    def all node: nil
      etcd(node: node)
      kubernetes(node: node)
      kubelet_ca(node: node)
    end

    def etcd node: nil
      hosts = etcd_hosts(node)
      etcd_opts = Porkadot::Install::KubeletList.new(global_config).etcd_options
      hosts.each do |host|
        install_etcd_assets(host)
        restart_etcd(host)
        wait_etcd_health(host, etcd_opts)
      end
      ''
    end

    def kubernetes node: nil
      host = kubernetes_host(node)
      Porkadot::Install::Kubernetes.new(global_config).install(host)
      restart_kubernetes_components(host)
      ''
    end

    def kubelet_ca node: nil
      hosts = kubelet_hosts(node)
      ca_path = global_config.kubelet_default.ca_crt_path

      on(hosts) do
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        upload! ca_path, File.join(Porkadot::Install::KUBE_TEMP, 'ca.crt')

        as user: 'root' do
          execute(:mkdir, '-p', '/etc/kubernetes/pki')
          execute(:cp, File.join(Porkadot::Install::KUBE_TEMP, 'ca.crt'), '/etc/kubernetes/pki/ca.crt')
        end
      end
      ''
    end

    def etcd_hosts node
      kubelets = Porkadot::Install::KubeletList.new(global_config)
      if node
        host = kubelets[node]
        raise Porkadot::Error, "Unknown node: #{node}" unless host
        raise Porkadot::Error, "Node is not an etcd member: #{node}" unless host.etcd?
        return [host]
      end

      kubelets.kubelets.values.select(&:etcd?)
    end

    def kubernetes_host node
      kubelets = Porkadot::Install::KubeletList.new(global_config)
      if node
        host = kubelets[node]
        raise Porkadot::Error, "Unknown node: #{node}" unless host
        return host
      end

      Porkadot::Install::Bootstrap.new(global_config).host
    end

    def kubelet_hosts node
      kubelets = Porkadot::Install::KubeletList.new(global_config)
      if node
        host = kubelets[node]
        raise Porkadot::Error, "Unknown node: #{node}" unless host
        return [host]
      end

      kubelets.kubelets.values
    end

    private

    def install_etcd_assets host
      on(host) do
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        if test("[ -d #{ETCD_TEMP} ]")
          execute(:rm, '-rf', ETCD_TEMP)
          execute(:rm, '-rf', ETCD_SECRETS_TEMP)
        end

        upload! host.config.target_path, ETCD_TEMP, recursive: true
        upload! host.config.target_secrets_path, ETCD_SECRETS_TEMP, recursive: true
        execute(:cp, '-r', ETCD_SECRETS_TEMP + '/*', ETCD_TEMP)

        as user: 'root' do
          execute(:bash, File.join(ETCD_TEMP, 'addons', 'etcd', 'install.sh'))
        end
      end
    end

    def restart_etcd host
      on(host) do
        as user: 'root' do
          with(container_runtime_endpoint: 'unix:///run/containerd/containerd.sock') do
            container = capture(:"/opt/bin/crictl", 'ps', '-q', '--name', 'etcd')
            execute(:"/opt/bin/crictl", 'stop', container) unless container.empty?
          end
        end
      end
    end

    def wait_etcd_health host, etcd_opts
      on(host) do
        until test(:"/opt/bin/etcdctl", *etcd_opts, 'endpoint', 'health')
          info "Still waiting for etcd health on #{host.hostname}"
          sleep 5
        end
      end
    end

    def restart_kubernetes_components hosts
      vip = global_config.k8s.control_plane_endpoint
      on(hosts) do
        kubeconfig = File.join(Porkadot::Install::Kubernetes::KUBE_SECRETS_TEMP, 'kubeconfig.yaml')
        with KUBECONFIG: kubeconfig do
          execute(:"/opt/bin/kubectl", '-n', 'kube-system', 'rollout', 'restart', 'daemonset/kube-apiserver')
          execute(:"/opt/bin/kubectl", '-n', 'kube-system', 'rollout', 'restart', 'deployment/kube-controller-manager')
          execute(:"/opt/bin/kubectl", '-n', 'kube-system', 'rollout', 'restart', 'deployment/kube-scheduler')
          execute(:"/opt/bin/kubectl", '--server', "https://#{vip}", '-n', 'kube-system', 'rollout', 'status', 'daemonset/kube-apiserver', '--timeout=600s')
          execute(:"/opt/bin/kubectl", '--server', "https://#{vip}", '-n', 'kube-system', 'rollout', 'status', 'deployment/kube-controller-manager', '--timeout=300s')
          execute(:"/opt/bin/kubectl", '--server', "https://#{vip}", '-n', 'kube-system', 'rollout', 'status', 'deployment/kube-scheduler', '--timeout=300s')
        end
      end
    end
  end
end; end
