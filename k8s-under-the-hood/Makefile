.PHONY: setup teardown verify demo-ep01 cleanup-ep01 help \
         tf-init tf-apply tf-destroy \
         templates \
         k3s-install observability-deploy \
         minio-status

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m # No Color

help:
	@echo "$(GREEN)Kubernetes Under the Hood Lab$(NC)"
	@echo ""
	@echo "$(YELLOW)Complete Setup (Recommended):$(NC)"
	@echo "  make setup          - Provision VMs, install K3s, deploy observability (one-time)"
	@echo ""
	@echo "$(YELLOW)Step-by-Step Setup (Advanced):$(NC)"
	@echo "  make tf-init        - Initialize Terraform"
	@echo "  make templates     - Bootstrap Ubuntu templates on Proxmox nodes (ONE-TIME, needs SSH)"
	@echo "  make tf-apply       - Provision VMs and MinIO (Terraform apply, API-only)"
	@echo "  make k3s-install    - Install K3s on all nodes (Ansible)"
	@echo "  make observability-deploy - Deploy Prometheus, Grafana, etc."
	@echo ""
	@echo "$(YELLOW)Lab Management:$(NC)"
	@echo "  make verify         - Verify lab health (nodes, pods, metrics)"
	@echo "  make minio-status   - Check MinIO status and endpoint"
	@echo "  make teardown       - Destroy all VMs and clean up"
	@echo ""
	@echo "$(YELLOW)Episode 1 - OOMKilled:$(NC)"
	@echo "  make demo-ep01      - Deploy demo workload and trigger OOMKill"
	@echo "  make cleanup-ep01   - Delete demo workloads (keep lab running)"
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@echo "  make help           - Show this help message"

# ============================================================================
# Complete Setup (One Command)
# ============================================================================

setup:
	@echo "$(GREEN)Setting up K8s Under the Hood lab...$(NC)"
	@echo "$(YELLOW)This will provision VMs, MinIO, K3s, and observability stack$(NC)"
	bash lab/scripts/setup.sh
	@echo "$(GREEN)✓ Lab setup complete!$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Verify the lab: make verify"
	@echo "  2. Run Episode 1: make demo-ep01"

# ============================================================================
# Step-by-Step Setup (Advanced)
# ============================================================================

tf-init:
	@echo "$(GREEN)Initializing Terraform...$(NC)"
	cd lab/terraform && terraform init

# ============================================================================
# One-Time Template Bootstrap
# ============================================================================
# This is the ONLY step that requires SSH access to Proxmox nodes
# (root@pve2, pve3, pve4). The image-to-disk import runs on each node.
#
# Prerequisites (on the controller running this):
#   1. Lab SSH key authorized on Proxmox nodes:
#      ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.47
#      ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.87
#      ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.25
#   2. Key loaded in ssh-agent (the provider reads the agent,
#      NOT ~/.ssh/config):
#      ssh-add lab/ssh/id_rsa
#
# After this succeeds once, all VM operations are API-only clones and
# every controller only needs the Proxmox API token.

templates:
	@echo "$(GREEN)Bootstrapping Ubuntu 24.04 templates on Proxmox nodes...$(NC)"
	@echo "$(YELLOW)This is a ONE-TIME step that requires SSH access to Proxmox nodes.$(NC)"
	@echo "$(YELLOW)Prerequisites: SSH key on root@pve2/pve3/pve4 + loaded in ssh-agent$(NC)"
	@echo "$(YELLOW)See 'make help' or templates.tf header for setup commands$(NC)"
	@echo ""
	@bash -c 'mkdir -p lab/ssh; \
	[ -f lab/ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -f lab/ssh/id_rsa -N "" -q; \
	if [ -z "$$PM_API_TOKEN_ID" ] || [ -z "$$PM_API_TOKEN_SECRET" ]; then \
		if [ -f ~/.proxmox-env ]; then \
			source ~/.proxmox-env; \
		else \
			echo "$(RED)Error: Proxmox credentials not set$(NC)"; \
			exit 1; \
		fi; \
	fi; \
	echo "$(YELLOW)Checking ssh-agent (provider requirement)...$(NC)"; \
	if ! ssh-add -L >/dev/null 2>&1; then \
		echo "$(RED)Error: no keys in ssh-agent$(NC)"; \
		echo "$(YELLOW)Run: ssh-add ~/.ssh/id_ed25519 (or your Proxmox-authorized key)$(NC)"; \
		exit 1; \
	fi; \
	cd lab/terraform && \
	terraform apply \
		-target=proxmox_virtual_environment_vm.ubuntu_template \
		-var "proxmox_api_token_id=$$PM_API_TOKEN_ID" \
		-var "proxmox_api_token_secret=$$PM_API_TOKEN_SECRET" \
		-var "ssh_public_key=$$(cat ../ssh/id_rsa.pub)" \
		-auto-approve'
	@echo "$(GREEN)✓ Templates created on pve2, pve3, pve4 (VM IDs 9100-9102)$(NC)"
	@echo "$(GREEN)✓ SSH is no longer needed for any lab operation$(NC)"
	@echo "$(YELLOW)Next: make tf-apply (works from ANY controller with just the API token)$(NC)"

tf-apply:
	@echo "$(GREEN)Applying Terraform (provisioning VMs and MinIO)...$(NC)"
	@echo "$(YELLOW)VMs are API-only clones of the per-node templates (no SSH needed)$(NC)"
	@echo "$(YELLOW)First run: templates must exist (make templates), downloads ~600MB image per node$(NC)"
	@bash -c 'read -p "Press Enter to continue..." && true'
	@bash -c 'mkdir -p lab/ssh; \
	[ -f lab/ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -f lab/ssh/id_rsa -N "" -q; \
	if [ -z "$$PM_API_TOKEN_ID" ] || [ -z "$$PM_API_TOKEN_SECRET" ]; then \
		if [ -f ~/.proxmox-env ]; then \
			source ~/.proxmox-env; \
		else \
			echo "$(RED)Error: Proxmox credentials not set$(NC)"; \
			exit 1; \
		fi; \
	fi; \
	cd lab/terraform && \
	terraform apply \
		-var "proxmox_api_token_id=$$PM_API_TOKEN_ID" \
		-var "proxmox_api_token_secret=$$PM_API_TOKEN_SECRET" \
		-var "ssh_public_key=$$(cat ../ssh/id_rsa.pub)" \
		-auto-approve'
	@echo "$(GREEN)✓ VMs and MinIO provisioned$(NC)"
	@echo "$(YELLOW)Next: make k3s-install$(NC)"

k3s-install:
	@echo "$(GREEN)Installing K3s on all nodes...$(NC)"
	@echo "$(YELLOW)Waiting for VMs to be fully ready (2-3 minutes)...$(NC)"
	@sleep 120
	@echo "$(YELLOW)Verifying SSH connectivity...$(NC)"
	@bash lab/scripts/setup.sh 2>&1 | grep -A 50 "Step 2: Installing K3s" || true
	@echo "$(GREEN)✓ K3s installed$(NC)"
	@echo "$(YELLOW)Next: make observability-deploy$(NC)"

observability-deploy:
	@echo "$(GREEN)Deploying observability stack...$(NC)"
	@bash -c 'export KUBECONFIG=~/.kube/config-k8suth; \
	cd lab/observability; \
	kubectl apply -f namespace.yaml; \
	kubectl apply -f prometheus.yaml; \
	kubectl apply -f grafana.yaml; \
	kubectl apply -f node-exporter.yaml; \
	kubectl apply -f kube-state-metrics.yaml; \
	echo "$(GREEN)✓ Observability stack deployed$(NC)"; \
	echo "$(YELLOW)Waiting for pods to be ready...$(NC)"; \
	kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s 2>/dev/null || true; \
	kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s 2>/dev/null || true; \
	echo "$(GREEN)✓ Observability stack ready$(NC)"'

# ============================================================================
# Lab Management
# ============================================================================

verify:
	@echo "$(GREEN)Verifying lab health...$(NC)"
	bash lab/scripts/verify.sh

minio-status:
	@echo "$(GREEN)MinIO Status$(NC)"
	@bash -c 'cd lab/terraform && \
	ENDPOINT=$$(terraform output -raw minio_endpoint 2>/dev/null || echo "http://192.168.1.81:9000"); \
	CONSOLE=$$(terraform output -raw minio_console_url 2>/dev/null || echo "http://192.168.1.81:9001"); \
	echo "API Endpoint: $$ENDPOINT"; \
	echo "Console URL: $$CONSOLE"; \
	echo "Credentials: minioadmin / minioadmin123"; \
	echo ""; \
	echo "Health check:"; \
	curl -s $$ENDPOINT/minio/health/live > /dev/null && echo "$(GREEN)✓ MinIO is running$(NC)" || echo "$(RED)✗ MinIO is not responding$(NC)"'

# ============================================================================
# Destroy Lab
# ============================================================================

tf-destroy:
	@echo "$(RED)Destroying Terraform infrastructure (VMs and MinIO)...$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		bash -c 'if [ -z "$$PM_API_TOKEN_ID" ] || [ -z "$$PM_API_TOKEN_SECRET" ]; then \
			if [ -f ~/.proxmox-env ]; then \
				source ~/.proxmox-env; \
			fi; \
		fi; \
		cd lab/terraform && \
		terraform destroy \
			-var "proxmox_api_token_id=$$PM_API_TOKEN_ID" \
			-var "proxmox_api_token_secret=$$PM_API_TOKEN_SECRET" \
			-var "ssh_public_key=$$(cat ../ssh/id_rsa.pub)" \
			-auto-approve'; \
		echo "$(GREEN)✓ Infrastructure destroyed$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

teardown:
	@echo "$(RED)Destroying entire lab (VMs, MinIO, observability)...$(NC)"
	@echo "$(YELLOW)This is equivalent to: make tf-destroy$(NC)"
	bash lab/scripts/teardown.sh
	@echo "$(GREEN)✓ Lab destroyed$(NC)"

# ============================================================================
# Episodes
# ============================================================================

demo-ep01:
	@echo "$(GREEN)Running Episode 1 - OOMKilled...$(NC)"
	bash episodes/01-oom-killed/scripts/demo.sh

cleanup-ep01:
	@echo "$(GREEN)Cleaning up Episode 1...$(NC)"
	bash episodes/01-oom-killed/scripts/cleanup.sh
	@echo "$(GREEN)✓ Episode 1 cleanup complete$(NC)"
	@echo "$(YELLOW)Lab is still running. Ready for next episode.$(NC)"
