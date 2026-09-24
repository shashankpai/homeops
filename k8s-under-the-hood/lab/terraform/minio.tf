# ==============================================================================
# MinIO Docker Container (on k8suth-master for Terraform state storage)
# ==============================================================================
# MinIO runs in a Docker container on the master node, providing S3-compatible
# object storage for Terraform state. This keeps state centralized and
# accessible from all controllers without NFS complexity.

resource "null_resource" "minio_docker_setup" {
  depends_on = [proxmox_virtual_environment_vm.master, time_sleep.wait_for_vms]

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo '=== Setting up MinIO Docker container ==='",

      # Update and install Docker
      "sudo apt-get update",
      "sudo apt-get install -y curl wget",
      "curl -fsSL https://get.docker.com -o /tmp/get-docker.sh",
      "sudo sh /tmp/get-docker.sh",
      "sudo usermod -aG docker ubuntu",

      # Create MinIO data directory
      "mkdir -p /tmp/minio/data",
      "sudo mkdir -p /minio/data",
      "sudo chown ubuntu:ubuntu /minio/data",
      "sudo chmod 755 /minio/data",

      # Wait for Docker daemon
      "sleep 5",

      # Start MinIO container
      "docker run -d \\",
      "  --name minio \\",
      "  --restart always \\",
      "  -p ${var.minio_config.api_port}:9000 \\",
      "  -p ${var.minio_config.console_port}:9001 \\",
      "  -e MINIO_ROOT_USER=${var.minio_config.root_user} \\",
      "  -e MINIO_ROOT_PASSWORD=${var.minio_config.root_password} \\",
      "  -v /minio/data:/data \\",
      "  minio/minio:latest \\",
      "  minio server /data --console-address ':9001'",

      "echo '=== MinIO started ==='",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path)
      host        = var.vm_ips["master"]
      timeout     = "5m"
    }
  }
}

# ==============================================================================
# Wait for MinIO to be ready
# ==============================================================================

resource "time_sleep" "wait_for_minio" {
  depends_on = [null_resource.minio_docker_setup]

  create_duration = "30s"  # Wait 30 seconds for MinIO to start
}

# ==============================================================================
# Create MinIO bucket via local-exec (after MinIO is ready)
# ==============================================================================

resource "null_resource" "minio_bucket_setup" {
  depends_on = [time_sleep.wait_for_minio]

  provisioner "local-exec" {
    command = templatefile("${path.module}/minio-setup.sh", {
      minio_endpoint      = "http://${var.minio_config.ip}:${var.minio_config.api_port}"
      minio_root_user     = var.minio_config.root_user
      minio_root_password = var.minio_config.root_password
      bucket_name         = var.minio_config.bucket_name
    })
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    minio_endpoint = "http://${var.minio_config.ip}:${var.minio_config.api_port}"
  }
}
