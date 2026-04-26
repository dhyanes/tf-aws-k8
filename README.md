# Kubernetes on AWS — Terraform

Provisions a self-managed Kubernetes cluster on AWS EC2:
- **1 Master node** (control plane, kubeadm bootstrapped)
- **2 Worker nodes** (joins automatically via token)
- **Flannel** as the CNI plugin
- Ubuntu 22.04 LTS base image
- Kubernetes **v1.29**

## Architecture

```
Internet
    │
    ▼
  IGW
    │
  VPC (10.0.0.0/16)
    │
  Public Subnet (10.0.1.0/24)
    ├── master   (t3.medium) ← SG: 6443, 22, etcd, kubelet
    ├── worker-1 (t3.medium) ← SG: 22, 10250, 30000-32767
    └── worker-2 (t3.medium) ← SG: 22, 10250, 30000-32767
```

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured (`aws configure`)
- An SSH key pair

## Quick Start

```bash
# 1. Clone / download this directory
cd k8s-aws/

# 2. Copy and fill in your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — add your SSH public key and IP

# 3. Initialize and apply
terraform init
terraform plan
terraform apply
```

## After Apply

```bash
# SSH to master
ssh -i ~/.ssh/id_rsa ubuntu@<master_public_ip>

# Check nodes (takes ~3-5 minutes to fully initialize)
kubectl get nodes

# Copy kubeconfig to your local machine
scp -i ~/.ssh/id_rsa ubuntu@<master_public_ip>:/home/ubuntu/.kube/config ~/.kube/config
kubectl get nodes   # from your local machine
```

## Manual Worker Join (fallback)

If the worker's auto-join fails, SSH to master and regenerate the token:

```bash
# On master
kubeadm token create --print-join-command

# Copy the output and run it on the worker node with sudo
```

## Tear Down

```bash
terraform destroy
```

## Notes

- **SSH between nodes**: The worker bootstrap script fetches the join token via SSH from master. Ensure your SSH key is available. For production, use AWS SSM Parameter Store or Secrets Manager instead.
- **Production hardening**: Use private subnets + NAT gateway, restrict `admin_cidr`, enable CloudTrail, and consider EKS for managed control plane.
- **Instance sizing**: `t3.medium` is the minimum. Use `t3.large` or `m5.large` for real workloads.
