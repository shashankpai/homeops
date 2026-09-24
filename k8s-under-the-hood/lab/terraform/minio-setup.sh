#!/bin/bash
set -e

# MinIO bucket setup script
# Creates bucket and enables versioning
#
# NOTE: uses the AWS CLI instead of the MinIO client (mc) because MinIO
# removed prebuilt binaries (dl.min.io returns 410 Gone, source-only
# distribution since late 2025). The S3 API is fully compatible.

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

export AWS_ACCESS_KEY_ID="$MINIO_USER"
export AWS_SECRET_ACCESS_KEY="$MINIO_PASSWORD"
export AWS_DEFAULT_REGION="us-east-1"

# Create bucket if it doesn't exist
if ! aws --endpoint-url "$MINIO_ENDPOINT" s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Creating bucket: $BUCKET_NAME"
  aws --endpoint-url "$MINIO_ENDPOINT" s3 mb "s3://$BUCKET_NAME"
else
  echo "Bucket already exists: $BUCKET_NAME"
fi

# Enable versioning
echo "Enabling versioning on bucket"
aws --endpoint-url "$MINIO_ENDPOINT" s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Verify
echo "=== MinIO bucket setup complete ==="
aws --endpoint-url "$MINIO_ENDPOINT" s3 ls
