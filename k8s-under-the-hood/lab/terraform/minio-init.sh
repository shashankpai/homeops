#!/bin/bash
set -e

# MinIO initialization script for LXC container
# Installs Docker and starts MinIO

echo "=== MinIO LXC Initialization ==="

# Update package lists
apt-get update
apt-get install -y curl wget gnupg2 lsb-release ca-certificates

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Create MinIO data directory
mkdir -p /minio/data
chmod 755 /minio/data

# Wait for Docker to be ready
sleep 5

# Start MinIO container
docker run -d \
  --name minio \
  --restart always \
  -p ${minio_api_port}:9000 \
  -p ${minio_console_port}:9001 \
  -e MINIO_ROOT_USER=${minio_root_user} \
  -e MINIO_ROOT_PASSWORD=${minio_root_password} \
  -v /minio/data:/data \
  minio/minio:latest \
  minio server /data --console-address ":9001"

echo "=== MinIO Started ==="
echo "API: http://0.0.0.0:${minio_api_port}"
echo "Console: http://0.0.0.0:${minio_console_port}"
