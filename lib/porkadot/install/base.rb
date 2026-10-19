require 'sshkit/dsl'
require 'net/ssh'

module Porkadot; module Install
  KUBE_TEMP = './kube_temp'
end; end

# SSHKit's own known_hosts parser returns only the first matching line of a
# hashed host, so a node whose rsa line comes before its ecdsa line fails with
# HostKeyMismatch. net-ssh's parser reads the same files and returns every
# matching line.
SSHKit::Backend::Netssh.configure do |ssh|
  ssh.ssh_options = { known_hosts: Net::SSH::KnownHosts }
end
