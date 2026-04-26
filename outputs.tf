################################################################################
# Outputs
################################################################################

output "master_public_ip" {
  description = "Public IP of the Kubernetes master node"
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Private IP of the Kubernetes master node"
  value       = aws_instance.master.private_ip
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = aws_instance.worker[*].public_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = aws_instance.worker[*].private_ip
}

output "ssh_master" {
  description = "SSH command to connect to master"
  value       = "ssh -i <your-key>.pem ubuntu@${aws_instance.master.public_ip}"
}

output "ssh_workers" {
  description = "SSH commands to connect to workers"
  value = [
    for w in aws_instance.worker :
    "ssh -i <your-key>.pem ubuntu@${w.public_ip}"
  ]
}

output "kubeconfig_command" {
  description = "Command to copy kubeconfig from master"
  value       = "scp -i <your-key>.pem ubuntu@${aws_instance.master.public_ip}:/home/ubuntu/.kube/config ~/.kube/config"
}
