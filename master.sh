#!/bin/bash
# Bootstrap script for Kubernetes Master Node
# Installs: containerd, kubeadm, kubelet, kubectl, Flannel CNI

set -euo pipefail
exec > >(tee /var/log/k8s-master-init.log) 2>&1

echo "=== [1/6] System preparation ==="
apt-get update -y
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Disable swap (required by kubeadm)
swapoff -a
sed -i '/swap/d' /etc/fstab

# Load required kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Kernel networking parameters
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "=== [2/6] Installing containerd ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y containerd.io

# Configure containerd with SystemdCgroup
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo "=== [3/6] Installing kubeadm, kubelet, kubectl ==="
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

echo "=== [4/6] Initializing Kubernetes cluster ==="
MASTER_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

kubeadm init \
  --pod-network-cidr="${pod_cidr}" \
  --apiserver-advertise-address="$MASTER_IP" \
  --apiserver-cert-extra-sans="$PUBLIC_IP,$MASTER_IP" \
  --node-name="$(hostname)" \
  --ignore-preflight-errors=NumCPU 2>&1 | tee /var/log/kubeadm-init.log

echo "=== [5/6] Configuring kubectl for ubuntu user ==="
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Also for root
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "=== [6/6] Installing Flannel CNI ==="
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml \
  --kubeconfig=/etc/kubernetes/admin.conf

echo "=== Saving join command for workers ==="
kubeadm token create --print-join-command > /tmp/k8s-join-command.sh
chmod 644 /tmp/k8s-join-command.sh

echo ""
echo "======================================================"
echo " Master node initialization COMPLETE!"
echo " Join command saved to: /tmp/k8s-join-command.sh"
echo " Kubeconfig: /home/ubuntu/.kube/config"
echo "======================================================"
