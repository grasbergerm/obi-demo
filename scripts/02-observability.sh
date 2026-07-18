#!/usr/bin/env bash
# Deploy the all-in-one Grafana LGTM stack (Grafana + Tempo + Prometheus + Loki
# + OTel Collector) that OBI will send telemetry to.
set -euo pipefail
cd "$(dirname "$0")/.."

# The demo dashboard ships as plain files; pack them into a ConfigMap that
# lgtm.yaml mounts into Grafana's provisioning directory.
kubectl --context kind-obi-demo create namespace observability \
  --dry-run=client -o yaml | kubectl --context kind-obi-demo apply -f -
kubectl --context kind-obi-demo -n observability create configmap grafana-demo-dashboard \
  --from-file=provider.yaml=k8s/grafana-dashboard-provider.yaml \
  --from-file=obi-demo.json=k8s/grafana-dashboard.json \
  --dry-run=client -o yaml | kubectl --context kind-obi-demo apply -f -

kubectl --context kind-obi-demo apply -f k8s/lgtm.yaml
kubectl --context kind-obi-demo -n observability rollout status deploy/lgtm --timeout=300s

echo
echo "LGTM stack is up. To open Grafana (user/pass admin/admin):"
echo "  kubectl --context kind-obi-demo -n observability port-forward svc/lgtm 3000:3000"
echo "  then open http://localhost:3000"
