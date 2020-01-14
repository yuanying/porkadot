# -*- mode: ruby -*-
# vi: set ft=ruby :

public_key = nil
[ENV['PORKA_PUBLIC_KEY'], "~/.ssh/id_rsa.pub", "~/.ssh/id_dsa.pub"].each do |p_key|
  if p_key
    p_key = File.expand_path(p_key)
    if File.file?(p_key)
      public_key = open(p_key).read
      break
    end
  end
end

unless public_key
  raise "Please specify ssh public key using following env: PORKA_PUBLIC_KEY"
end

SCRIPT = <<-EOF
echo "#{public_key}" >> ~vagrant/.ssh/authorized_keys

apt update
apt install -y socat conntrack ipset
EOF

CNI_INSTALL = <<-EOF
CNI_VERSION="v0.8.2"
mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz
EOF

K8S_INSTALL = <<-EOF
RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"

mkdir -p /opt/bin
cd /opt/bin
curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
chmod +x {kubeadm,kubelet,kubectl}

curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/kubelet.service" | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service
mkdir -p /etc/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/10-kubeadm.conf" | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
EOF

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"
  config.vm.box_check_update = true

  [[:node01, 111], [:node02, 112], [:node03, 113], [:node04, 114]].each do |worker|
    config.vm.define worker[0] do |w|
      w.vm.hostname = worker[0].to_s
      w.vm.provider "virtualbox" do |v, override|
        v.customize ["modifyvm", :id, "--memory", "2048"]
      end

      w.vm.network :private_network, ip: "192.168.33.#{worker[1]}"
      w.vm.provision "docker", images: ["busybox"]
      w.vm.provision :shell, inline: SCRIPT
      w.vm.provision :shell, inline: CNI_INSTALL
      w.vm.provision :shell, inline: K8S_INSTALL
    end
  end
end
