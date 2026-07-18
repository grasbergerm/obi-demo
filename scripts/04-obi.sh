#!/usr/bin/env bash
# Deploy OpenTelemetry eBPF Instrumentation (OBI) via Helm.
# This is the moment telemetry starts flowing, with zero application changes.
set -euo pipefail
cd "$(dirname "$0")/.."

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null

helm upgrade --install obi open-telemetry/opentelemetry-ebpf-instrumentation \
  --kube-context kind-obi-demo \
  --namespace obi --create-namespace \
  -f obi-values.yaml

kubectl --context kind-obi-demo -n obi rollout status daemonset -l app.kubernetes.io/name=opentelemetry-ebpf-instrumentation --timeout=180s

echo
echo "OBI is running. Give it ~30s, then check for traces and metrics:"
echo "  ./scripts/verify.sh"
