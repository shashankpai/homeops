.PHONY: setup teardown verify demo-ep01 cleanup-ep01 help

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m # No Color

help:
	@echo "$(GREEN)Kubernetes Under the Hood Lab$(NC)"
	@echo ""
	@echo "$(YELLOW)Lab Management:$(NC)"
	@echo "  make setup          - Provision VMs, install K3s, deploy observability (one-time)"
	@echo "  make verify         - Verify lab health (nodes, pods, metrics)"
	@echo "  make teardown       - Destroy all VMs and clean up"
	@echo ""
	@echo "$(YELLOW)Episode 1 - OOMKilled:$(NC)"
	@echo "  make demo-ep01      - Deploy demo workload and trigger OOMKill"
	@echo "  make cleanup-ep01   - Delete demo workloads (keep lab running)"
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@echo "  make help           - Show this help message"

# Lab setup (one-time)
setup:
	@echo "$(GREEN)Setting up K8s Under the Hood lab...$(NC)"
	@echo "$(YELLOW)Step 1: Provisioning VMs...$(NC)"
	bash lab/scripts/setup.sh
	@echo "$(GREEN)✓ Lab setup complete!$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Verify the lab: make verify"
	@echo "  2. Run Episode 1: make demo-ep01"

# Verify lab health
verify:
	@echo "$(GREEN)Verifying lab health...$(NC)"
	bash lab/scripts/verify.sh

# Episode 1: OOMKilled
demo-ep01:
	@echo "$(GREEN)Running Episode 1 - OOMKilled...$(NC)"
	bash episodes/01-oom-killed/scripts/demo.sh

# Episode 1: Cleanup
cleanup-ep01:
	@echo "$(GREEN)Cleaning up Episode 1...$(NC)"
	bash episodes/01-oom-killed/scripts/cleanup.sh
	@echo "$(GREEN)✓ Episode 1 cleanup complete$(NC)"
	@echo "$(YELLOW)Lab is still running. Ready for next episode.$(NC)"

# Destroy the lab
teardown:
	@echo "$(RED)Destroying lab (this will delete all VMs)...$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		bash lab/scripts/teardown.sh; \
		echo "$(GREEN)✓ Lab destroyed$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi
