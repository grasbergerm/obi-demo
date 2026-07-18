#!/usr/bin/env bash
# Phase 2: replace the backend with an SDK-instrumented build.
# OBI detects the service now exports its own OTLP traces and suppresses its
# own traces for it, no double-counting, while still emitting span metrics
# and service-graph metrics for it.
set -euo pipefail
cd "$(dirname "$0")/.."

docker build --build-arg SERVICE=backend-sdk -t obi-demo/backend:v2-sdk app/
kind load docker-image obi-demo/backend:v2-sdk --name obi-demo

kubectl --context kind-obi-demo apply -f k8s/backend-sdk.yaml
kubectl --context kind-obi-demo -n demo rollout status deploy/backend --timeout=180s

echo
echo "backend now runs the SDK-instrumented build. Within a minute you should see:"
echo "  - backend traces now carry telemetry.sdk.language=go and the custom"
echo "    'calculate-quote' span with a business attribute"
echo "  - OBI has stopped emitting its own backend traces (no duplicates)"
echo "  - frontend traces still come from OBI"
echo "Run ./scripts/verify.sh to check from the terminal."
