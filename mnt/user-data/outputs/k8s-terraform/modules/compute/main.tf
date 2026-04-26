################################################################################
# Module: compute
# Creates key pair, master EC2 instance, and worker EC2 instances
################################################################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.cluster_name}-key"
  public_key = var.public_key_material
  tags       = var.tags
}

# ─── Master Node ─────────────────────────────────────────────────────────────

resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [var.master_sg_id]
  iam_instance_profile   = var.master_instance_profile

  root_block_device {
    volume_size           = var.master_disk_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = var.encrypt_volumes
  }

  user_data = base64encode(templatefile("${path.module}/scripts/master.sh", {
    pod_cidr     = var.pod_network_cidr
    cluster_name = var.cluster_name
  }))

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-master"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                        = "master"
  })
}

# ─── Worker Nodes ────────────────────────────────────────────────────────────

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [var.worker_sg_id]
  iam_instance_profile   = var.worker_instance_profile

  root_block_device {
    volume_size           = var.worker_disk_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = var.encrypt_volumes
  }

  user_data = base64encode(templatefile("${path.module}/scripts/worker.sh", {
    master_private_ip = aws_instance.master.private_ip
    cluster_name      = var.cluster_name
  }))

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-worker-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                        = "worker"
  })

  depends_on = [aws_instance.master]
}
