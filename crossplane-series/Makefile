.PHONY: help crossplane-install crossplane-uninstall verify \
         xp-core xp-provider xp-providerconfig xp-functions \
         demo-ep01 demo-ep01-step cleanup-ep01

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
	@echo "    ...or phase by phase (same as the lab-guide manual steps):"
	@echo "  make xp-core               - Section 7:  Helm install Crossplane core"
	@echo "  make xp-provider           - Section 9:  runtime config + RBAC + provider-kubernetes"
	@echo "  make xp-providerconfig     - Section 10: ProviderConfig (InjectedIdentity)"
	@echo "  make xp-functions          - Section 15: composition functions"
	@echo "  make verify                - Health check: lab nodes, crossplane pods, providers"
	@echo "  make crossplane-uninstall  - Remove Crossplane (lab stays running)"
	@echo ""
	@echo "$(YELLOW)Episode 1 - Getting Started:$(NC)"
	@echo "  make demo-ep01             - Run the whole episode 1 demo (interactive)"
	@echo "  make demo-ep01-step STEP=n - Run ONE demo phase (0 tour, 1 MRs, 2 drift, 3 XRD+Composition,"
	@echo "                               4 create WebApp, 5 update, 6 trace+delete). Needs earlier steps done."
	@echo "  make cleanup-ep01          - Delete episode workloads (Crossplane stays installed)"
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@echo "  make help                  - Show this help"

crossplane-install:
	bash lab/install-crossplane.sh

xp-core:
	. ./lab/versions.env && helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
	helm repo update >/dev/null 2>&1
	. ./lab/versions.env && helm upgrade --install crossplane crossplane-stable/crossplane \
		--namespace crossplane-system --create-namespace --version "$$CROSSPLANE_CHART_VERSION" --wait --timeout 5m
	kubectl get pods -n crossplane-system

xp-provider:
	kubectl apply -f lab/providers/10-runtime-config.yaml
	kubectl apply -f lab/providers/20-rbac.yaml
	kubectl apply -f lab/providers/00-provider.yaml
	kubectl wait --for=condition=Healthy provider/provider-kubernetes --timeout=300s
	kubectl get provider provider-kubernetes

xp-providerconfig:
	kubectl apply -f lab/providers/30-provider-config.yaml
	kubectl get providerconfigs.kubernetes.crossplane.io

xp-functions:
	kubectl apply -f lab/providers/40-functions.yaml
	kubectl wait --for=condition=Healthy function/function-patch-and-transform function/function-auto-ready --timeout=300s
	kubectl get functions

crossplane-uninstall:
	bash lab/uninstall-crossplane.sh

verify:
	bash lab/verify.sh

demo-ep01:
	bash episodes/01-getting-started/scripts/demo.sh

demo-ep01-step:
	@test -n "$(STEP)" || { echo "usage: make demo-ep01-step STEP=0..6"; exit 1; }
	STEP=$(STEP) bash episodes/01-getting-started/scripts/demo.sh

cleanup-ep01:
	bash episodes/01-getting-started/scripts/cleanup.sh
