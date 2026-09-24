output "master_ip" {
  description = "Master node IP address"
  value       = var.vm_ips["master"]
}

output "worker1_ip" {
  description = "Worker 1 node IP address"
  value       = var.vm_ips["worker1"]
}

output "worker2_ip" {
  description = "Worker 2 node IP address"
  value       = var.vm_ips["worker2"]
}

output "cluster_nodes" {
  description = "All cluster node IPs"
  value = {
    master  = var.vm_ips["master"]
    worker1 = var.vm_ips["worker1"]
    worker2 = var.vm_ips["worker2"]
  }
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${var.vm_ips["master"]}:6443"
}

output "ssh_command" {
  description = "SSH command to connect to master"
  value       = "ssh -i lab/ssh/id_rsa ubuntu@${var.vm_ips["master"]}"
}

output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = "~/.kube/config-k8suth"
}

output "vm_placement" {
  description = "Which Proxmox node hosts each VM (no VMs on pve/.48)"
  value = {
    master  = "k8suth-master (${var.vm_ips["master"]}) on ${var.vm_nodes["master"]}"
    worker1 = "k8suth-worker1 (${var.vm_ips["worker1"]}) on ${var.vm_nodes["worker1"]}"
    worker2 = "k8suth-worker2 (${var.vm_ips["worker2"]}) on ${var.vm_nodes["worker2"]}"
  }
}

output "minio_endpoint" {
  description = "MinIO S3 API endpoint"
  value       = "http://${var.minio_config.ip}:${var.minio_config.api_port}"
}

output "minio_console_url" {
  description = "MinIO Web Console URL"
  value       = "http://${var.minio_config.ip}:${var.minio_config.console_port}"
}

output "minio_credentials" {
  description = "MinIO root credentials"
  value = {
    access_key = var.minio_config.root_user
    secret_key = var.minio_config.root_password
  }
  sensitive = true
}

output "terraform_backend_config" {
  description = "Terraform S3 backend configuration for MinIO"
  value       = <<-EOT
terraform {
  backend "s3" {
    bucket         = "${var.minio_config.bucket_name}"
    key            = "k8s-under-the-hood/terraform.tfstate"
    region         = "us-east-1"
    endpoint       = "http://${var.minio_config.ip}:${var.minio_config.api_port}"
    access_key     = "${var.minio_config.root_user}"
    secret_key     = "${var.minio_config.root_password}"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
  EOT
}

output "next_steps" {
  description = "Next steps after Terraform apply"
  value       = <<-EOT
    Terraform apply complete!

    VM placement (no VMs on the main node pve/.48):
      k8suth-master  (${var.vm_ips["master"]}) on ${var.vm_nodes["master"]}
      k8suth-worker1 (${var.vm_ips["worker1"]}) on ${var.vm_nodes["worker1"]}
      k8suth-worker2 (${var.vm_ips["worker2"]}) on ${var.vm_nodes["worker2"]}

    MinIO State Backend:
      Endpoint: http://${var.minio_config.ip}:${var.minio_config.api_port}
      Console:  http://${var.minio_config.ip}:${var.minio_config.console_port}
      Creds:    ${var.minio_config.root_user} / ${var.minio_config.root_password}

    Next steps:
    1. Wait for VMs and MinIO to boot (2-3 minutes; first run also downloads the
       Ubuntu cloud image ~600MB per node — subsequent runs reuse it)
    2. Run Ansible playbook to install K3s:
       cd lab/ansible
       ansible-playbook -i inventory.ini k3s-cluster.yml

    3. Copy kubeconfig to your Mac:
       scp -i lab/ssh/id_rsa ubuntu@${var.vm_ips["master"]}:~/.kube/config ~/.kube/config-k8suth
       sed -i '' 's/127.0.0.1/${var.vm_ips["master"]}/g' ~/.kube/config-k8suth

    4. Verify cluster:
       export KUBECONFIG=~/.kube/config-k8suth
       kubectl get nodes

    5. Deploy observability stack:
       kubectl apply -f lab/observability/

    6. Run Episode 1:
       make demo-ep01
  EOT
}
