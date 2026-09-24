# Multi-Controller Setup Guide

Execute the K8s Under the Hood lab from any control machine (Mac, Linux servers, etc.) with centralized state management.

---

## Overview

This guide enables you to:

1. **Execute from any controller** — Mac, Linux servers, or any machine with Terraform/Ansible/kubectl
2. **Share Terraform state** — Centralized state backend prevents conflicts
3. **Access from anywhere** — kubeconfig and SSH keys accessible to all controllers
4. **Maintain consistency** — Single source of truth for infrastructure

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
│   │ Terraform    │      │ Terraform    │                 │
│   │ State        │      │ State        │                 │
│   │ (S3/TF Cloud)│      │ (S3/TF Cloud)│                 │
│   └──────────────┘      └──────────────┘                 │
│         │                       │                         │
│         └───────────┬───────────┘                         │
│                     ↓                                      │
│         ┌───────────────────────┐                         │
│         │   Proxmox Cluster     │                         │
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

6. **SSH client**
   ```bash
   ssh -V  # OpenSSH (built-in on Mac/Linux)
   ```

### Installation by OS

**macOS (using Homebrew)**
```bash
brew install terraform ansible kubectl jq
```

**Ubuntu/Debian**
```bash
sudo apt-get update
sudo apt-get install -y terraform ansible kubectl jq
```

**RHEL/CentOS**
```bash
sudo yum install -y terraform ansible kubectl jq
```

---

## Setup Steps

### Step 1: Clone the Repository on Each Controller

```bash
# On each control machine
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood
```

### Step 2: Set Up Proxmox API Token (One-Time, Any Controller)

Create the token once on your Proxmox cluster:

```bash
ssh root@192.168.1.48
pveum user token add root@pam k8s-under-the-hood --privsep 0
# Copy the secret shown
```

### Step 3: Configure Terraform Remote State Backend

This ensures all controllers use the same state file.

#### Option A: Terraform Cloud (Recommended)

**1. Create a Terraform Cloud account**
- Go to https://app.terraform.io
- Sign up (free tier available)
- Create an organization (e.g., `your-homeops`)

**2. Create an API token**
- User settings → Tokens
- Create an API token
- Copy the token

**3. Create a backend configuration file**

On **each controller**, create `lab/terraform/backend.tf`:

```hcl
terraform {
  cloud {
    organization = "your-homeops"  # Replace with your org name

    workspaces {
      name = "k8s-under-the-hood"
    }
  }
}
```

**4. Authenticate Terraform**

On each controller:

```bash
cd /path/to/homeops/k8s-under-the-hood/lab/terraform
terraform login
# Paste your API token when prompted
```

This creates `~/.terraform/credentials.tfrc.json` with your token.

#### Option B: AWS S3 (If You Have AWS)

**1. Create an S3 bucket**
```bash
aws s3 mb s3://your-homeops-terraform-state --region us-east-1
```

**2. Create `lab/terraform/backend.tf`**

```hcl
terraform {
  backend "s3" {
    bucket         = "your-homeops-terraform-state"
    key            = "k8s-under-the-hood/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

**3. Create DynamoDB table for state locking**
```bash
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

**4. Configure AWS credentials on each controller**
```bash
aws configure
# Enter your AWS access key and secret
```

#### Option C: Local NFS Share (If You Have Shared Storage)

**1. Mount NFS on each controller**
```bash
# On each controller
mkdir -p ~/shared-terraform-state
sudo mount -t nfs 192.168.1.100:/export/terraform-state ~/shared-terraform-state
```

**2. Create `lab/terraform/backend.tf`**
```hcl
terraform {
  backend "local" {
    path = "~/shared-terraform-state/k8s-under-the-hood/terraform.tfstate"
  }
}
```

### Step 4: Set Up Environment Variables

On **each controller**, create `~/.proxmox-env`:

```bash
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<secret-from-step-2>"
EOF

chmod 600 ~/.proxmox-env
```

### Step 5: Initialize Terraform Backend

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
# On any controller
cd /path/to/homeops/k8s-under-the-hood
source ~/.proxmox-env
make setup
```

### Verify the Lab

```bash
make verify
```

### Access from Any Controller

```bash
# Set kubeconfig (stored on your Mac or shared location)
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

## Sharing kubeconfig and SSH Keys

### Option A: Store in Git (Not Recommended)

⚠️ **WARNING**: Never commit secrets to git!

### Option B: Shared NFS Mount (Recommended)

**1. Mount shared storage on all controllers**
```bash
mkdir -p ~/shared-k8s-config
sudo mount -t nfs 192.168.1.100:/export/k8s-config ~/shared-k8s-config
```

**2. Update Terraform to output kubeconfig to shared location**

Edit `lab/terraform/outputs.tf`:
```hcl
output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = "~/shared-k8s-config/config-k8suth"
}
```

**3. Update setup.sh to copy kubeconfig to shared location**

Edit `lab/scripts/setup.sh`:
```bash
# Copy kubeconfig to shared location
mkdir -p ~/shared-k8s-config
scp -i "$SSH_DIR/id_rsa" ubuntu@"$MASTER_IP":~/.kube/config ~/shared-k8s-config/config-k8suth
```

**4. On each controller, set kubeconfig**
```bash
export KUBECONFIG=~/shared-k8s-config/config-k8suth
```

### Option C: 1Password/Vault (Enterprise)

If you use 1Password, Vault, or similar:

**1. Store kubeconfig in 1Password**
```bash
op item create --category "Document" \
  --title "k8s-under-the-hood kubeconfig" \
  --body "$(cat ~/.kube/config-k8suth)"
```

**2. Retrieve on any controller**
```bash
op item get "k8s-under-the-hood kubeconfig" --fields label=body > ~/.kube/config-k8suth
chmod 600 ~/.kube/config-k8suth
```

### Option D: SSH Agent Forwarding (Simplest)

**1. On your primary Mac, add SSH key to agent**
```bash
ssh-add -K lab/ssh/id_rsa
```

**2. On any controller, use SSH agent forwarding**
```bash
# SSH to a Linux server with agent forwarding
ssh -A user@linux-server

# Now you can SSH to Proxmox VMs from the Linux server
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81
```

---

## Workflow Example: Multi-Controller Setup

### Controller 1: Mac (Primary)

```bash
# Clone repo
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood

# Set up Terraform Cloud backend
cat > lab/terraform/backend.tf << 'EOF'
terraform {
  cloud {
    organization = "your-homeops"
    workspaces {
      name = "k8s-under-the-hood"
    }
  }
}
EOF

# Initialize and bring up lab
source ~/.proxmox-env
cd lab/terraform
terraform init
terraform apply

# Set kubeconfig
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
```

### Controller 2: Linux Server

```bash
# Clone repo
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood

# Terraform automatically uses the remote backend
source ~/.proxmox-env
cd lab/terraform
terraform init
# No need to apply — state is shared with Mac

# Access the cluster
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
```

---

## Best Practices

### 1. State Management

✅ **DO**
- Use remote state backend (Terraform Cloud, S3, etc.)
- Enable state locking (prevents concurrent modifications)
- Encrypt state at rest
- Backup state regularly

❌ **DON'T**
- Commit terraform.tfstate to git
- Use local state across multiple controllers
- Share state via unencrypted channels

### 2. Credentials

✅ **DO**
- Store API tokens in environment variables
- Use `~/.proxmox-env` with `chmod 600`
- Rotate tokens periodically
- Use different tokens per environment (dev/prod)

❌ **DON'T**
- Hardcode tokens in Terraform files
- Commit `.env` files to git
- Share tokens via Slack/email
- Use the same token for multiple purposes

### 3. Access Control

✅ **DO**
- Restrict SSH key permissions (`chmod 600`)
- Use SSH agent forwarding for remote access
- Limit kubeconfig access (RBAC)
- Audit who accesses the lab

❌ **DON'T**
- Share SSH keys via email
- Store kubeconfig in public locations
- Use root credentials
- Allow unauthenticated access

### 4. Coordination

✅ **DO**
- Designate one controller as "primary" for setup
- Document who's running what and when
- Use Terraform locking to prevent conflicts
- Communicate state changes to the team

❌ **DON'T**
- Run `terraform apply` from multiple controllers simultaneously
- Modify state files directly
- Assume another controller isn't making changes
- Skip the `terraform plan` step

---

## Troubleshooting

### "Error: Error acquiring the state lock"

**Cause**: Another controller is running Terraform.

**Solution**:
```bash
# Wait for the other controller to finish
# Or force-unlock (use with caution):
terraform force-unlock <LOCK_ID>
```

### "Error: Invalid API token"

**Cause**: Token not set or expired.

**Solution**:
```bash
# Verify token
echo $PM_API_TOKEN_ID
echo $PM_API_TOKEN_SECRET

# If empty, source the env file
source ~/.proxmox-env

# If token expired, create a new one
ssh root@192.168.1.48
pveum user token add root@pam k8s-under-the-hood --privsep 0
```

### "Error: kubeconfig not found"

**Cause**: kubeconfig not copied to the controller.

**Solution**:
```bash
# Copy from primary controller
scp user@primary-controller:~/.kube/config-k8suth ~/.kube/config-k8suth
chmod 600 ~/.kube/config-k8suth

# Or retrieve from shared location
cp ~/shared-k8s-config/config-k8suth ~/.kube/config-k8suth
```

### "Error: SSH key permission denied"

**Cause**: SSH key permissions are too open.

**Solution**:
```bash
chmod 600 lab/ssh/id_rsa
chmod 644 lab/ssh/id_rsa.pub
```

---

## Recommended Setup

For your use case (Mac + Linux servers), I recommend:

### 1. **State Backend**: Terraform Cloud (Free tier)
- ✅ No infrastructure to manage
- ✅ Built-in state locking
- ✅ Web UI for state inspection
- ✅ Easy to set up

### 2. **Credentials**: Environment Variables
- ✅ Secure (not in git)
- ✅ Easy to rotate
- ✅ Works on all OS

### 3. **kubeconfig**: Shared NFS Mount
- ✅ Accessible from all controllers
- ✅ Single source of truth
- ✅ Easy to backup

### 4. **SSH Keys**: Generated Locally, Shared via SSH Agent
- ✅ Never transmitted
- ✅ Works across controllers
- ✅ Secure forwarding

### 5. **Coordination**: Designate Primary Controller
- ✅ One controller runs `make setup`
- ✅ Others run `make verify` and access
- ✅ Clear ownership

---

## Quick Setup (Terraform Cloud)

```bash
# 1. Create Terraform Cloud account and org
# 2. Create API token
# 3. On each controller:

cd /path/to/homeops/k8s-under-the-hood

# Create backend config
cat > lab/terraform/backend.tf << 'EOF'
terraform {
  cloud {
    organization = "your-homeops"
    workspaces {
      name = "k8s-under-the-hood"
    }
  }
}
EOF

# Authenticate
terraform login
# Paste your API token

# Initialize
cd lab/terraform
terraform init

# On primary controller only:
source ~/.proxmox-env
terraform apply

# On other controllers:
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
```

---

## Summary

| Aspect | Recommendation |
|--------|-----------------|
| **State Backend** | Terraform Cloud (free tier) |
| **Credentials** | Environment variables (~/.proxmox-env) |
| **kubeconfig** | Shared NFS mount or 1Password |
| **SSH Keys** | Generated locally, SSH agent forwarding |
| **Coordination** | Designate primary controller |
| **Execution** | Any controller can run `make setup` |
| **Access** | All controllers can access the lab |

This setup enables you to execute the lab from any controller while maintaining a single source of truth for infrastructure state.
