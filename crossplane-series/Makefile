.PHONY: help crossplane-install crossplane-uninstall verify \
         demo-ep01 cleanup-ep01

GREEN  := \033[0;32m
YELLOW := \033[0;33m
NC     := \033[0m

KUBECONFIG ?= $(HOME)/.kube/config-k8suth
export KUBECONFIG

help:
	@echo "$(GREEN)Crossplane Series Lab$(NC)"
	@echo ""
	@echo "$(YELLOW)Lab (reuses ../k8s-under-the-hood K3s cluster):$(NC)"
	@echo "  make crossplane-install    - Install Crossplane v2 + providers + functions (one-time)"
	@echo "  make verify                - Health check: lab nodes, crossplane pods, providers"
	@echo "  make crossplane-uninstall  - Remove Crossplane (lab stays running)"
	@echo ""
	@echo "$(YELLOW)Episode 1 - Getting Started:$(NC)"
	@echo "  make demo-ep01             - Run the episode 1 demo (interactive)"
	@echo "  make cleanup-ep01          - Delete episode workloads (Crossplane stays installed)"
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@echo "  make help                  - Show this help"

crossplane-install:
	bash lab/install-crossplane.sh

crossplane-uninstall:
	bash lab/uninstall-crossplane.sh

verify:
	bash lab/verify.sh

demo-ep01:
	bash episodes/01-getting-started/scripts/demo.sh

cleanup-ep01:
	bash episodes/01-getting-started/scripts/cleanup.sh
