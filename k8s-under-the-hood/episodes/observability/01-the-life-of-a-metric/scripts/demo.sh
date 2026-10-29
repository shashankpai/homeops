#!/bin/bash
# =============================================================================
# Observability Episode 01 — The Life of a Metric
#
# A read-only descent: follow ONE data point (node_memory_MemAvailable_bytes)
# from the pixel on a Grafana dashboard down to the kernel counter in
# /proc/meminfo where it was born. Six links of custody, traced backwards.
#
# Flow (the descent):
#   1. Preflight: lab up, Prometheus reachable, pick the victim node
#   2. Link 6 — the pixel (Grafana pointers + the 15s sampling)
#   3. Link 5 — the query (PromQL table view: what a series IS)
#   4. Link 4 — the vault (TSDB self-metrics: head series, heartbeat)
#   5. Link 3 — the scrape (targets page, up, scrape duration, discovery)
#   6. Link 2 — the exposition (curl node-exporter /metrics directly)
#   7. Link 1 — the kernel (ssh: grep MemAvailable /proc/meminfo)
#   8. The full chain forward + the arc's failure map
#
# NOTE: this episode deploys NOTHING and changes NOTHING. Read-only by design.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_SSH_KEY="${LAB_SSH_KEY:-$EP_DIR/../../../lab/ssh/id_rsa}"
PROM_URL="${PROM_URL:-http://192.168.1.81:30900}"
GRAFANA_URL="${GRAFANA_URL:-http://192.168.1.81:30300}"

pause() { echo -e "\n${YELLOW}>>> $1 — press Enter to continue${NC}"; read -r; }
banner() { echo -e "\n${CYAN}===================================================================$NC"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}===================================================================$NC"; }
prom() { curl -s --data-urlencode "query=$1" "$PROM_URL/api/v1/query" \
           | python3 -c "import json,sys; [print(f\"{m['metric'].get('instance', m['metric'].get('job','?')):<40} {m['value'][1]}\") for m in json.load(sys.stdin)['data']['result']]" 2>/dev/null \
           || echo "(query failed — is Prometheus reachable at $PROM_URL ?)"; }

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

banner "OBSERVABILITY EPISODE 01: The Life of a Metric"

# --- 1. Preflight ------------------------------------------------------------
banner "STEP 1 — Preflight: the lab, and the node we'll descend into"

echo -e "${YELLOW}Monitoring namespace:${NC}"
kubectl get pods -n monitoring

echo ""
if curl -s "$PROM_URL/-/healthy" >/dev/null; then
    echo -e "${GREEN}✓ Prometheus reachable at $PROM_URL${NC}"
else
    echo -e "${RED}✗ Prometheus NOT reachable — start the lab first (make verify)${NC}"
    exit 1
fi

# pick a worker node (node names are IPs in this lab; resolve InternalIP anyway)
NODE=$(kubectl get nodes -l 'node-role.kubernetes.io/agent' -o jsonpath='{.items[0].metadata.name}')
NODE_IP=$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
echo -e "${GREEN}Victim node:${NC} $NODE ($NODE_IP) — its node-exporter :9100 is Link 2's address"

pause "Preflight complete"

# --- 2. Link 6: the pixel ----------------------------------------------------
banner "STEP 2 — LINK 6: The Pixel (Grafana)"

echo "Open: $GRAFANA_URL  (admin/admin)"
echo "Dashboard: 'Episode OBS-01 — The Life of a Metric' (import if needed:"
echo "  episodes/observability/01-the-life-of-a-metric/dashboards/life-of-a-metric.json)"
echo ""
echo -e "${YELLOW}On the 'The Data Point' panel:${NC}"
echo "  - zoom IN until you see the sampling: 15s between dots"
echo "  - the smooth line is a LIE of smoothness — Grafana paints between samples"
echo "  - between every pair of dots, 15 seconds of reality went unobserved"
echo "  - (Season 1 paced its leak at 2MB/2s for exactly this reason)"
echo ""
echo -e "${YELLOW}The pixel is a painting over samples. Grafana stores nothing —"
echo -e "${YELLOW} it asks a question and someone answers. Link 5 finds the question.${NC}"

pause "The pixel, decoded"

# --- 3. Link 5: the query ----------------------------------------------------
banner "STEP 3 — LINK 5: The Query — what a series actually IS"

echo "In the Prometheus UI ($PROM_URL), run:"
echo ""
echo "  node_memory_MemAvailable_bytes"
echo ""
echo "then switch Graph -> TABLE. A series = NAME + LABEL SET:"
echo ""
prom "node_memory_MemAvailable_bytes"
echo ""
echo "And how many series live in this one family?"
echo ""
prom "count(node_memory_MemAvailable_bytes)"
echo ""
echo -e "${YELLOW}Mental model: name = WHAT, labels = WHICH. One family, many series${NC}"
echo -e "${YELLOW}— add a label with N values, get N new series. Remember this${NC}"
echo -e "${YELLOW}rule; Episode 04 turns it into an incident.${NC}"

pause "The series, defined"

# --- 4. Link 4: the vault ----------------------------------------------------
banner "STEP 4 — LINK 4: The Vault — TSDB, interrogated about itself"

echo -e "${YELLOW}Prometheus scrapes its own /metrics (job 'prometheus') — so the"
echo -e "${YELLOW}database can be queried ABOUT the database:${NC}"
echo ""
echo "  Series in the hot head block (memory-resident):"
prom "prometheus_tsdb_head_series"
echo ""
echo "  The pipeline's heartbeat — samples/second arriving:"
prom "rate(prometheus_tsdb_head_samples_appended_total[1m])"
echo ""
echo -e "${YELLOW}Series count tracks memory almost LINEARLY — this number is the"
echo -e "${YELLOW}single most important Prometheus metric, and the lever Episode 04 pulls.${NC}"

pause "The vault, quantified"

# --- 5. Link 3: the scrape ----------------------------------------------------
banner "STEP 5 — LINK 3: The Delivery Run — the scrape"

echo "Prometheus UI -> Status -> Targets: every delivery route."
echo "  - node-exporter: one target PER NODE; kube-state-metrics; kubelets;"
echo "    cAdvisor; prometheus itself"
echo ""
echo -e "${YELLOW}The delivery health pair (Prometheus writes these itself, per scrape):${NC}"
echo ""
echo "  up — the delivery receipt (1 = last scrape succeeded):"
prom "up{job='node-exporter'}"
echo ""
echo "  scrape_duration_seconds — how long the delivery took:"
prom "scrape_duration_seconds{job='node-exporter'}"
echo ""
echo -e "${YELLOW}PULL, not push: the vault waits at home; a delivery run every 15s.${NC}"
echo -e "${YELLOW}When a target gets too heavy, duration climbs toward 15s, up flips"
echo -e "${YELLOW}to 0, and graphs develop holes. (Episode 07 — taste it now.)${NC}"
echo ""
echo -e "${YELLOW}Where does the target list come from? Service discovery —"
echo -e "${YELLOW}see lab/observability/prometheus.yaml, job 'node-exporter':"
echo -e "${YELLOW}kubernetes_sd finds pods labeled app=node-exporter and rewrites"
echo -e "${YELLOW}the address from the prometheus.io/port annotation. New node ->"
echo -e "${YELLOW}DaemonSet plants an exporter -> appears in targets, zero config.${NC}"

pause "The delivery run, witnessed"

# --- 6. Link 2: the exposition ------------------------------------------------
banner "STEP 6 — LINK 2: The Translator — the exposition format"

echo -e "${YELLOW}node-exporter runs hostNetwork — its endpoint IS the node's."
echo -e "${YELLOW}Skip the middleman; read the source directly:${NC}"
echo ""
echo "  curl -s http://$NODE_IP:9100/metrics | head -20"
echo ""
curl -s "http://$NODE_IP:9100/metrics" | head -20 || echo "(curl failed — check the node-exporter pod on $NODE)"
echo ""
echo -e "${YELLOW}The exposition: HELP / TYPE / series lines. Plain text, one endpoint.${NC}"
echo ""
echo "Now find OUR data point:"
echo ""
echo "  curl -s http://$NODE_IP:9100/metrics | grep -A2 MemAvailable"
echo ""
curl -s "http://$NODE_IP:9100/metrics" | grep -A2 "MemAvailable" || true
echo ""
echo -e "${YELLOW}A stateless translator: it remembers NOTHING — it renders the"
echo -e "${YELLOW}current truth on demand. The TIME dimension isn't in the exporter;"
echo -e "${YELLOW}the vault builds the history by sampling this every 15 seconds.${NC}"

pause "The translator, read raw"

# --- 7. Link 1: the kernel ----------------------------------------------------
banner "STEP 7 — LINK 1: The Origin — the kernel counter"

echo -e "${YELLOW}The exporter mounts the host /proc read-only. SSH to the node"
echo -e "${YELLOW}and read the SAME file it reads:${NC}"
echo ""
if ssh -i "$LAB_SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ubuntu@$NODE_IP" "grep MemAvailable /proc/meminfo" 2>/dev/null; then
    echo ""
    echo -e "${GREEN}Multiply by 1024 — the SAME number the exporter served${NC}"
    echo -e "${GREEN}(kernel speaks kB, Prometheus speaks bytes — the chain converts).${NC}"
else
    echo -e "${RED}(SSH failed — run manually: ssh -i lab/ssh/id_rsa ubuntu@$NODE_IP 'grep MemAvailable /proc/meminfo')${NC}"
fi

echo ""
echo -e "${YELLOW}/proc is the kernel's API. MemAvailable is the kernel's own"
echo -e "${YELLOW}estimate of what it could hand out. Our data point was BORN here.${NC}"

pause "The origin, witnessed"

# --- 8. The full chain --------------------------------------------------------
banner "STEP 8 — The full chain, forward — and every way it breaks"

cat << 'CHAIN'
  THE LIFE OF A METRIC:

    kernel counter -> exporter -> scrape (15s) -> TSDB -> query -> pixel
       /proc        translation   delivery run    vault   lookup  painting

  EVERY LINK HAS A FAILURE MODE — each is a later episode in this arc:

  | exporter->scrape | too many series to serialize        | Ep 04 Cardinality   |
  | TSDB            | too many series to store (own limit) | Ep 04 Cardinality   |
  | scrape->vault   | target down, samples stop            | Ep 07 Graph Holes   |
  | the observers   | four sources, three numbers          | Ep 08 Three Numbers |
  | query->pixel    | averages and buckets that hide       | Ep 09 The Avg Lie   |
  | pixel->human    | alert fired, nobody was paged        | Ep 05 Alert Nobody  |
  | all of it       | who watches the watcher?             | Ep 06 Dead Man's    |
CHAIN

echo ""
echo -e "${GREEN}You now know the machine. The rest of the arc is every way it${NC}"
echo -e "${GREEN}betrays you — and how to make each link honest again.${NC}"
echo ""
echo -e "${CYAN}Next: Episode 02 — The Four Observers.${NC}"
echo ""
echo -e "${GREEN}Demo complete (read-only — nothing to clean).${NC}"
