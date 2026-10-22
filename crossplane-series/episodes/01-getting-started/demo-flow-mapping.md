# Episode 1 — Concept → Command Mapping

Narration phase → the command that proves it (all in lab-guide.md; demo.sh runs them in order).

| Phase | Concept (what you say) | Command / manifest (what you show) |
|---|---|---|
| 1 | The promise: drift heals itself, nobody ran anything | Cold open: `kubectl -n demo-team-a delete configmap welcome` → heal loop |
| 2 | Pipeline model + its three structural flaws | Diagram; `terraform plan` exit-code-2 cron story (no terminal) |
| 3 | Control plane = the Deployment loop, pointed at infra | Diagram; callback to k8s-shorts control-loop Short |
| 4 | One Helm release; core = package manager + CRDs | `helm upgrade --install crossplane ...`; `kubectl get crd \| grep -c crossplane` |
| 5 | Provider = CRDs + controllers + identity, as an OCI package | `kubectl apply -f lab/providers/00-provider.yaml`; `kubectl get provider -w`; `kubectl get crd \| grep kubernetes.crossplane.io` |
| 5 | Provider SA + RBAC is real platform engineering | `lab/providers/10-runtime-config.yaml`, `20-rbac.yaml` |
| 6 | Credentials are resources in the API | `kubectl apply -f lab/providers/30-provider-config.yaml` (InjectedIdentity, 5 lines) |
| 7 | MR anatomy: forProvider / providerConfigRef; spec down, status up | `manifests/01-managed-resources.yaml`; `kubectl get objects...` (READY/SYNCED); `-o yaml` annotations |
| 7 | "kubectl get IS terraform state list" | `kubectl get ns demo-team-a`; `kubectl -n demo-team-a get cm welcome -o yaml` |
| 8 | Level-triggered: 3 attacks, 3 correct responses | delete → heal; `kubectl patch cm` → revert; `kubectl delete object` → cascade |
| 8 | removalPolicy: Delete vs Orphan (adopting infra) | `removalPolicy: Orphan` heredoc → `kubectl delete object` → CM survives (lab-guide §13) |
| 9 | You are an API author; Kubernetes learns a new word | `kubectl apply -f manifests/02-xrd.yaml`; `kubectl get crd webapps...`; `kubectl explain webapp` |
| 10 | Functions RENDER, controllers CREATE | `manifests/03-composition.yaml` (pipeline); `kubectl get functions` |
| 10 | Offline render = unit-testing your platform | `crossplane beta render manifests/04-webapp.yaml manifests/03-composition.yaml` |
| 11 | 9 lines → whole environment | `kubectl apply -f manifests/04-webapp.yaml`; `kubectl -n payments-team get all,cm` |
| 11 | Trace = incident response for infra | `crossplane beta trace webapp/payments` |
| 11 | Update = a chain of control loops | `kubectl patch webapp payments -p '{"spec":{"replicas":4}}'` → `watch` the Deployment |
| 11 | It's real: consume it | `port-forward service/webapp` + `curl` |
| 11 | Controlled teardown | `kubectl delete webapp payments` → namespace gone |
| 12 | The verdict + litmus test ("who notices a 2am change?") | Comparison table graphic; "Terraform built this very lab" callback |
