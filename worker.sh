#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/k8s-worker-init.log) 2>&1

MASTER_IP="${master_private_ip}"

echo "=== [1/5] System prep ==="
apt-get update -y && apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

swapoff -a
sed -i '/swap/d' /etc/fstab

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "=== [2/5] containerd ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y && apt-get install -y containerd.io
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd && systemctl enable containerd

echo "=== [3/5] kubeadm / kubelet ==="
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

echo "=== [4/5] Waiting for master ==="
until curl -sk "https://$MASTER_IP:6443/healthz" | grep -q "ok"; do
  echo "  Waiting for $MASTER_IP:6443 ..."
  sleep 10
done

echo "=== [5/5] Joining cluster ==="
for i in $(seq 1 20); do
  JOIN_CMD=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    ubuntu@"$MASTER_IP" "cat /tmp/k8s-join-command.sh" 2>/dev/null || true)
  [ -n "$JOIN_CMD" ] && break
  echo "  Waiting for join token (attempt $i/20)..."
  sleep 15
done

if [ -z "$JOIN_CMD" ]; then
  echo "ERROR: Could not get join command. SSH to master and run kubeadm token create --print-join-command"
  exit 1
fi

eval "$JOIN_CMD"
echo "Worker joined cluster — master: $MASTER_IP"
