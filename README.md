# Kubernetes on AWS — Modular Terraform

Self-managed Kubernetes cluster (1 master + 2 workers) with fully reusable modules
and separate configs for **dev**, **staging**, and **prod**.

## Repository Structure

```
k8s-terraform/
├── modules/
│   ├── vpc/                  # VPC, IGW, subnet, route table
│   ├── security-groups/      # Master + worker SGs
│   ├── iam/                  # IAM roles & instance profiles
│   └── compute/              # Key pair, master EC2, worker EC2s
│       └── scripts/
│           ├── master.sh     # kubeadm init + Flannel CNI
│           └── worker.sh     # kubeadm join
└── environments/
    ├── dev/                  # t3.small workers, no encryption, open SSH
    ├── staging/              # t3.medium, encrypted volumes, IP-restricted SSH
    └── prod/                 # t3.large, encrypted volumes, locked CIDR, bigger disks
```

## Environment Comparison

| Setting              | dev         | staging     | prod        |
|----------------------|-------------|-------------|-------------|
| Master instance      | t3.medium   | t3.medium   | t3.large    |
| Worker instance      | t3.small    | t3.medium   | t3.large    |
| Worker count         | 2           | 2           | 2           |
| Master disk (GB)     | 20          | 30          | 50          |
| Worker disk (GB)     | 15          | 20          | 40          |
| EBS encryption       | ✗           | ✓           | ✓           |
| VPC CIDR             | 10.10.0.0/16| 10.20.0.0/16| 10.30.0.0/16|
| admin_cidr default   | 0.0.0.0/0   | explicit IP | explicit IP |

## Quick Start

```bash
# Pick an environment
cd environments/dev    # or staging / prod

# Fill in your values
cp terraform.tfvars terraform.tfvars.local
# Edit: set public_key_material and admin_cidr

# Deploy
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## After Apply

```bash
# Outputs give you ready-to-use commands:
terraform output ssh_master
terraform output kubeconfig_cmd

# Check nodes (~3-5 min after apply)
kubectl get nodes
```

## Remote State (Recommended for staging/prod)

Uncomment the `backend "s3"` block in each environment's `main.tf` and create:
- An S3 bucket for state files
- A DynamoDB table (`tf-lock`) for state locking

## Tear Down

```bash
cd environments/dev
terraform destroy
```
