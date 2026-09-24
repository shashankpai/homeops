# Multi-Controller Setup with MinIO (Lightweight S3-Compatible State Backend)

Execute the K8s Under the Hood lab from any control machine using MinIO for Terraform state — lightweight, S3-compatible, runs in Docker.

---

## Overview

This guide enables you to:

1. **Execute from any controller** — Mac, Linux servers, or any machine with Terraform/Ansible/kubectl
2. **Store Terraform state in MinIO** — Lightweight S3-compatible object storage
3. **Access from anywhere** — Centralized state without NFS complexity
4. **Maintain consistency** — Single source of truth for infrastructure

---

## Why MinIO?

| Feature | MinIO | NFS | Terraform Cloud | AWS S3 |
|---------|-------|-----|-----------------|--------|
| **Setup** | 1 Docker command | Complex NFS setup | Cloud account | AWS account |
| **Size** | ~100MB | N/A | Cloud | Cloud |
| **Cost** | Free (self-hosted) | Free (if you have NAS) | Free tier limited | Pay per use |
| **Complexity** | Simple | Medium | Simple | Medium |
| **Local Control** | Full | Full | Limited | Limited |
| **S3 Compatible** | Yes | No | No | Yes |
| **Single Binary** | Yes (Docker) | No | N/A | N/A |
| **Lightweight** | Yes | N/A | N/A | N/A |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Control Machines                    │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────┐               │
│  │  Mac (primary)   │  │  Linux server 1  │               │
│  │  /Users/...      │  │  /home/user/...  │               │
│  └────────┬─────────┘  └────────┬─────────┘               │
│           │                     │                          │
│           └─────────────────────┘                          │
│                     │                                      │
│                     ↓                                      │
│         ┌───────────────────────┐                         │
│         │   Git Repository      │                         │
│         │   (homeops on GitHub) │                         │
│         └───────────┬───────────┘                         │
│                     │                                      │
│         ┌───────────┴───────────┐                         │
│         ↓                       ↓                          │
│   ┌──────────────┐      ┌──────────────┐                 │
│   │  Terraform   │      │  Terraform   │                 │
│   │  State       │      │  State       │                 │
│   │  (S3 API)    │      │  (S3 API)    │                 │
│   └──────────────┘      └──────────────┘                 │
│         │                       │                         │
│         └───────────┬───────────┘                         │
│                     ↓                                      │
│         ┌───────────────────────┐                         │
│         │   MinIO Container     │                         │
│         │   (S3-compatible)     │                         │
│         │   Port 9000 (API)     │                         │
│         │   Port 9001 (Web UI)  │                         │
│         └───────────┬───────────┘                         │
│                     ↓                                      │
│         ┌───────────────────────┐                         │
│         │   Proxmox Host or     │                         │
│         │   Linux Server        │                         │
│         │   (192.168.1.48)      │                         │
│         └───────────────────────┘                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### All Controllers Need

1. **Git**
   ```bash
   git --version  # v2.0+
   ```

2. **Terraform**
   ```bash
   terraform version  # v1.5+
   ```

3. **Ansible**
   ```bash
   ansible --version  # v2.10+
   ```

4. **kubectl**
   ```bash
   kubectl version --client  # v1.36+
   ```

5. **jq**
   ```bash
   jq --version
   ```

6. **AWS CLI** (optional, for testing MinIO)
   ```bash
   aws --version
   ```

### MinIO Server Host

You need one machine to run MinIO. Options:

**Option A: Proxmox Host (192.168.1.48) — RECOMMENDED**
- Already running
- Accessible from all controllers
- Docker installed

**Option B: Dedicated Linux Server**
- Separate from Proxmox
- Full control
- Docker installed

**Option C: Docker on Your Mac**
- For testing only
- Not recommended for production

---

## Setup Steps

### Step 1: Set Up MinIO Server

**Option A: MinIO on Proxmox Host (Recommended)**

```bash
# SSH to Proxmox host
ssh root@192.168.1.48

# Create MinIO data directory
mkdir -p /minio/data

# Create MinIO container
docker run -d \
  --name minio \
  --restart always \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  -v /minio/data:/data \
  minio/minio:latest \
  minio server /data --console-address ":9001"

# Verify MinIO is running
docker ps | grep minio
curl http://localhost:9000/minio/health/live
```

**Option B: MinIO on Dedicated Linux Server**

```bash
# SSH to Linux server
ssh user@linux-server

# Install Docker (if not already installed)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Create MinIO data directory
mkdir -p ~/minio/data

# Create MinIO container
docker run -d \
  --name minio \
  --restart always \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  -v ~/minio/data:/data \
  minio/minio:latest \
  minio server /data --console-address ":9001"

# Verify MinIO is running
docker ps | grep minio
curl http://localhost:9000/minio/health/live
```

### Step 2: Create MinIO Bucket for Terraform State

```bash
# SSH to MinIO host
ssh root@192.168.1.48  # or your Linux server

# Install MinIO client (mc)
curl https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Configure MinIO alias
mc alias set minio http://localhost:9000 minioadmin minioadmin123

# Create bucket for Terraform state
mc mb minio/terraform-state

# Enable versioning (recommended for state files)
mc version enable minio/terraform-state

# Verify bucket
mc ls minio/
```

### Step 3: Create MinIO Access Keys for Terraform

```bash
# SSH to MinIO host
ssh root@192.168.1.48

# Create a dedicated user for Terraform (more secure than root)
mc admin user add minio terraform-user terraform-password123

# Grant permissions to the bucket
mc admin policy attach minio readwrite --user terraform-user

# Verify user
mc admin user list minio
```

**Save these credentials:**
- Access Key: `terraform-user`
- Secret Key: `terraform-password123`
- MinIO Endpoint: `http://192.168.1.48:9000` (or your Linux server IP)

### Step 4: Clone Repository on Each Controller

```bash
# On each control machine
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood
```

### Step 5: Create Proxmox API Token (One-Time, Any Controller)

```bash
ssh root@192.168.1.48
pveum user token add root@pam k8s-under-the-hood --privsep 0
# Copy the secret shown
```

### Step 6: Create Terraform Backend Configuration

On **each controller**, create `lab/terraform/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "k8s-under-the-hood/terraform.tfstate"
    region         = "us-east-1"  # MinIO requires a region, can be any value
    endpoint       = "http://192.168.1.48:9000"  # MinIO endpoint
    access_key     = "terraform-user"
    secret_key     = "terraform-password123"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
```

**Important**: Replace `192.168.1.48` with your MinIO server IP if different.

### Step 7: Set Up Environment Variables

On **each controller**, create `~/.proxmox-env`:

```bash
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<secret-from-step-5>"
EOF

chmod 600 ~/.proxmox-env
```

### Step 8: Initialize Terraform Backend

On **one controller only** (the first time):

```bash
cd /path/to/homeops/k8s-under-the-hood/lab/terraform
source ~/.proxmox-env
terraform init
```

On **subsequent controllers**, just run:
```bash
cd /path/to/homeops/k8s-under-the-hood/lab/terraform
terraform init
# Terraform will detect the remote backend and configure it
```

---

## Execution from Any Controller

### Bring Up the Lab

```bash
# On the primary controller (Mac)
cd /path/to/homeops/k8s-under-the-hood
source ~/.proxmox-env
make setup
```

### Verify the Lab

```bash
# On any controller
make verify
```

### Access from Any Controller

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/config-k8suth

# Check cluster
kubectl get nodes

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

### Destroy the Lab

```bash
make teardown
```

---

## Monitoring MinIO

### Web UI

Access MinIO's web console:

```
http://192.168.1.48:9001
Username: minioadmin
Password: minioadmin123
```

### Check Terraform State in MinIO

```bash
# SSH to MinIO host
ssh root@192.168.1.48

# List objects in bucket
mc ls minio/terraform-state/

# View state file
mc cat minio/terraform-state/k8s-under-the-hood/terraform.tfstate | jq .
```

### MinIO Metrics

```bash
# Check MinIO health
curl http://192.168.1.48:9000/minio/health/live

# Check MinIO cluster info
docker exec minio mc admin info minio
```

---

## Troubleshooting

### "Error: error reading S3 Bucket"

**Cause**: MinIO not running or endpoint unreachable.

**Solution**:
```bash
# Check MinIO is running
docker ps | grep minio

# Check MinIO is accessible
curl http://192.168.1.48:9000/minio/health/live

# Check logs
docker logs minio
```

### "Error: InvalidAccessKeyId"

**Cause**: Wrong access key or secret key.

**Solution**:
```bash
# Verify credentials in backend.tf
cat lab/terraform/backend.tf | grep -E "access_key|secret_key"

# Verify user exists in MinIO
ssh root@192.168.1.48
docker exec minio mc admin user list minio
```

### "Error: NoSuchBucket"

**Cause**: Bucket doesn't exist in MinIO.

**Solution**:
```bash
# SSH to MinIO host
ssh root@192.168.1.48

# Create bucket
docker exec minio mc mb minio/terraform-state

# Enable versioning
docker exec minio mc version enable minio/terraform-state

# Verify
docker exec minio mc ls minio/
```

### "Error: Error acquiring the state lock"

**Cause**: Another controller is running Terraform or lock file is stuck.

**Solution**:
```bash
# Wait for other controller to finish
# Or check MinIO for lock file
ssh root@192.168.1.48
docker exec minio mc ls minio/terraform-state/k8s-under-the-hood/

# If stuck, remove lock (use with caution)
docker exec minio mc rm minio/terraform-state/k8s-under-the-hood/.terraform.lock.hcl
```

### MinIO container keeps restarting

**Cause**: Port conflict or permission issue.

**Solution**:
```bash
# Check logs
docker logs minio

# Check if ports are in use
netstat -tlnp | grep 9000
netstat -tlnp | grep 9001

# Stop and remove container
docker stop minio
docker rm minio

# Recreate with different ports (if needed)
docker run -d \
  --name minio \
  --restart always \
  -p 9010:9000 \
  -p 9011:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  -v /minio/data:/data \
  minio/minio:latest \
  minio server /data --console-address ":9001"
```

---

## Best Practices

### 1. State Management

✅ **DO**
- Enable versioning on MinIO bucket
- Backup MinIO data regularly
- Use strong passwords for MinIO
- Monitor MinIO health

❌ **DON'T**
- Use default credentials (minioadmin/minioadmin123) in production
- Expose MinIO to the internet
- Delete state files manually

### 2. Credentials

✅ **DO**
- Store MinIO credentials in backend.tf (it's not in git)
- Use dedicated MinIO user for Terraform (not root)
- Rotate credentials periodically
- Keep ~/.proxmox-env out of git

❌ **DON'T**
- Hardcode credentials in environment variables
- Commit backend.tf to git (add to .gitignore)
- Share MinIO credentials via Slack/email

### 3. Security

✅ **DO**
- Restrict MinIO access to your network (firewall)
- Use strong passwords
- Enable HTTPS in production (use reverse proxy)
- Monitor MinIO access logs

❌ **DON'T**
- Expose MinIO to the internet
- Use weak passwords
- Run MinIO as root
- Disable authentication

### 4. Coordination

✅ **DO**
- Designate one controller as "primary" for setup
- Document who's running what and when
- Wait for Terraform to finish before running from another controller
- Communicate state changes to the team

❌ **DON'T**
- Run `terraform apply` from multiple controllers simultaneously
- Modify state files directly
- Assume another controller isn't making changes

---

## Workflow Example: Multi-Controller Setup with MinIO

### Controller 1: Mac (Primary)

```bash
# Clone repo
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood

# Create backend.tf
cat > lab/terraform/backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "k8s-under-the-hood/terraform.tfstate"
    region         = "us-east-1"
    endpoint       = "http://192.168.1.48:9000"
    access_key     = "terraform-user"
    secret_key     = "terraform-password123"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
EOF

# Set credentials
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<your-secret>"
EOF
chmod 600 ~/.proxmox-env

# Initialize and bring up lab
source ~/.proxmox-env
cd lab/terraform
terraform init
cd ../..
make setup
```

### Controller 2: Linux Server

```bash
# Clone repo
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood

# Create backend.tf (same as Mac)
cat > lab/terraform/backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "k8s-under-the-hood/terraform.tfstate"
    region         = "us-east-1"
    endpoint       = "http://192.168.1.48:9000"
    access_key     = "terraform-user"
    secret_key     = "terraform-password123"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
EOF

# Set credentials
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<your-secret>"
EOF
chmod 600 ~/.proxmox-env

# Initialize (detects shared state)
source ~/.proxmox-env
cd lab/terraform
terraform init

# Access the cluster
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
```

---

## Quick Setup (15 Minutes)

### 1. Start MinIO (5 minutes)

```bash
ssh root@192.168.1.48

mkdir -p /minio/data

docker run -d \
  --name minio \
  --restart always \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  -v /minio/data:/data \
  minio/minio:latest \
  minio server /data --console-address ":9001"

# Wait for MinIO to start
sleep 5

# Create bucket
curl -X POST http://localhost:9000/minio/v6.0.0/admin/v1/buckets \
  -H "Authorization: AWS4-HMAC-SHA256 Credential=minioadmin/20240101/us-east-1/s3/aws4_request" \
  -d '{"Name":"terraform-state"}'

# Or use mc
docker exec minio mc mb minio/terraform-state
docker exec minio mc version enable minio/terraform-state
```

### 2. Configure Controllers (5 minutes each)

```bash
cd /path/to/homeops/k8s-under-the-hood

cat > lab/terraform/backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "k8s-under-the-hood/terraform.tfstate"
    region         = "us-east-1"
    endpoint       = "http://192.168.1.48:9000"
    access_key     = "minioadmin"
    secret_key     = "minioadmin123"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
EOF

cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<your-secret>"
EOF
chmod 600 ~/.proxmox-env

source ~/.proxmox-env
cd lab/terraform && terraform init
cd ../..
```

### 3. Bring Up Lab (5 minutes)

```bash
make setup
```

---

## Summary

| Aspect | Solution |
|--------|----------|
| **State Backend** | MinIO (S3-compatible) |
| **MinIO Host** | Proxmox host (192.168.1.48) or Linux server |
| **MinIO Deployment** | Docker container |
| **Bucket** | terraform-state (with versioning) |
| **Access Key** | terraform-user |
| **Credentials** | Stored in backend.tf (not in git) |
| **Proxmox Token** | Environment variables (~/.proxmox-env) |
| **Coordination** | Designate primary controller (Mac) |
| **Execution** | Any controller can run make setup |
| **Access** | All controllers can access the lab |

---

## Advantages Over NFS

| Aspect | MinIO | NFS |
|--------|-------|-----|
| **Setup** | 1 Docker command | Complex NFS setup |
| **Complexity** | Simple | Medium |
| **Size** | ~100MB | N/A |
| **S3 Compatible** | Yes | No |
| **Web UI** | Yes (port 9001) | No |
| **Monitoring** | Built-in | No |
| **Backup** | Easy (docker volume) | Complex |
| **Scaling** | Easy (MinIO cluster) | Hard |

---

## Next Steps

1. **Start MinIO** on Proxmox host (1 Docker command)
2. **Create bucket** for Terraform state
3. **Configure controllers** with backend.tf
4. **Initialize Terraform** on each controller
5. **Bring up lab** from primary controller
6. **Access from any controller** with kubectl

This setup is lightweight, simple, and gives you centralized state management without the complexity of NFS or the dependency on cloud services.
