# Crossplane Getting Started — YouTube Metadata

## Titles (pick 1)

**Primary:** Crossplane Explained: Infrastructure as Kubernetes, No Terraform Required (Full Demo)

1. **Crossplane Getting Started: Turn Kubernetes into a Platform in 25 Minutes** — beginner-friendly, duration signalled
2. **Crossplane vs Terraform: Which One Should You Actually Use? (Live Demo)** — comparison is the highest-intent search
3. **I Deleted a ConfigMap and Crossplane Fixed It — The End of Infrastructure Drift?** — hook-first, mirrors the under-the-hood cold-open style
4. **What Is Crossplane? The Kubernetes-Native Way to Manage Infrastructure** — pure search keyword title
5. **Stop Running Terraform: Kubernetes Can Be Your Control Plane** — spicy, thumbnail-friendly

## Description draft

What if your infrastructure was just... Kubernetes? In this episode we install Crossplane v2 on a real K3s cluster (Provisioned by Terraform on Proxmox — the irony is intentional), create managed resources with no cloud credentials, fight the control plane and lose, and then build our own platform API: one 9-line YAML that provisions an entire environment.

⏱ Chapters
00:00 The promise (drift heals itself)
01:00 Crossplane vs Terraform — the real difference
07:00 What installing Crossplane actually gives you
09:00 Your first managed resource
13:00 Drift: fighting the control plane
17:00 XRDs + Compositions: your own platform API
22:00 Cleanup, recap, what's next

🔗 Repo: github.com/<you>/homeops → crossplane-series
🖥 Lab: same 3-node K3s cluster as the "K8s Under the Hood" series

## Tags

crossplane, crossplane tutorial, crossplane v2, crossplane terraform, infrastructure as code, platform engineering, kubernetes infrastructure, xrd, composition, kubectl, gitops, k3s, homelab

## Thumbnail concepts

1. Split: Terraform logo w/ "state: 400MB" vs Crossplane logo w/ "no state file"
2. "9 lines of YAML" over a screenshot of the full composed environment
3. `kubectl delete` → 🔁 auto-heal loop arrow

## Notes

- Pin comment: link to under-the-hood Ep (control loop) — audience overlap.
- The Terraform-comparison segment 2 is the searchable evergreen core; also cut it as a standalone Short ("Crossplane vs Terraform in 60 seconds").
