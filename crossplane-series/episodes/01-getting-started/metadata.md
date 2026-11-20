# Crossplane Getting Started — YouTube Metadata

## Titles (pick 1)

**Primary:** Crossplane Explained: Infrastructure as Kubernetes, No Terraform Required (Full Deep Dive)

1. **Crossplane Getting Started: The Complete Beginner's Deep Dive (with Live Demo)** — beginner-friendly, duration signalled
2. **Crossplane vs Terraform: Which One Should You Actually Use? (Honest Verdict + Demo)** — comparison is the highest-intent search
3. **I Deleted a ConfigMap and the Cluster Healed It — Meet Crossplane** — hook-first, mirrors the under-the-hood cold-open style
4. **What Is Crossplane? Providers, XRDs, Compositions — Everything, From Zero** — pure search keyword title
5. **Stop Running Terraform: Kubernetes Can Be Your Infrastructure Control Plane** — spicy, thumbnail-friendly

## Description draft

What if your infrastructure was just... Kubernetes? In this full getting-started deep dive we install Crossplane v2 on a real K3s cluster (provisioned by Terraform on Proxmox — the irony is intentional), and build every concept from zero: providers as packages, credentials without secrets, your first managed resources, a live drift fight (three attacks — delete, edit, delete-the-managed-resource), the removal policy, publishing your own API with XRDs, compositions as function pipelines, offline rendering in CI, and the honest Crossplane-vs-Terraform verdict at the end.

Everything in the video is in the repo: install scripts, runnable lab guide with every manual command, and the exact manifests.

⏱ Chapters
00:00 The promise (drift heals itself, nobody ran anything)
01:30 The problem with infrastructure-as-a-pipeline
04:00 The control plane model (you already know it)
07:00 Installing Crossplane (one Helm release)
09:00 Providers: what they actually are (vocabulary, workers, identity)
14:00 ProviderConfig: identity all the way to the cloud (tokens, secrets, Workload Identity)
19:00 Managed resources: the atom of Crossplane (full anatomy)
25:00 The drift fight: three attacks, three correct responses
29:30 XRDs: publish your own kind (validation for free)
33:00 Compositions: a pure function for your platform (and offline render in CI)
38:30 The payoff: 9 lines of YAML → a whole environment
43:30 The honest verdict: Crossplane vs Terraform
47:10 What's next

🔗 Repo: github.com/shashankpai/homeops → crossplane-series
🖥 Lab: same 3-node K3s cluster as the "K8s Under the Hood" series

## Tags

crossplane, crossplane tutorial, crossplane v2, crossplane getting started, crossplane terraform, infrastructure as code, platform engineering, kubernetes infrastructure, xrd, composition, crossplane provider, kubectl, gitops, k3s, homelab

## Thumbnail concepts

1. Split: Terraform logo w/ "state: 400MB" vs Crossplane logo w/ "no state file"
2. "9 lines of YAML" over a screenshot of the full composed environment
3. `kubectl delete` → 🔁 auto-heal loop arrow

## Notes

- Pin comment: link to the k8s-shorts control-loop Short — the "control plane model" phase leans on it.
- Phase 12 (vs Terraform) and the cold open are the two cuttable Shorts.
- Duration ~48 min is intentional: this is the series reference episode. Chapter timestamps are mandatory for retention.
