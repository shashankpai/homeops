#!/bin/bash
set -e

# MinIO bucket setup script
# Creates bucket and enables versioning

MINIO_ENDPOINT="${minio_endpoint}"
MINIO_USER="${minio_root_user}"
MINIO_PASSWORD="${minio_root_password}"
BUCKET_NAME="${bucket_name}"

echo "=== Setting up MinIO bucket ==="

# Wait for MinIO to be ready
for i in {1..30}; do
  if curl -s "$MINIO_ENDPOINT/minio/health/live" > /dev/null; then
    echo "MinIO is ready"
    break
  fi
  echo "Waiting for MinIO... ($i/30)"
  sleep 2
done

# Install MinIO client if not present
if ! command -v mc &> /dev/null; then
  echo "Installing MinIO client..."
  curl https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
  chmod +x /usr/local/bin/mc
fi

# Configure MinIO alias
mc alias set minio "$MINIO_ENDPOINT" "$MINIO_USER" "$MINIO_PASSWORD" --api S3v4

# Create bucket
if ! mc ls minio/$BUCKET_NAME > /dev/null 2>&1; then
  echo "Creating bucket: $BUCKET_NAME"
  mc mb minio/$BUCKET_NAME
else
  echo "Bucket already exists: $BUCKET_NAME"
fi

# Enable versioning
echo "Enabling versioning on bucket"
mc version enable minio/$BUCKET_NAME

# Verify
echo "=== MinIO bucket setup complete ==="
mc ls minio/
