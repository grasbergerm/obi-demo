#!/usr/bin/env bash
# Build and deploy the (uninstrumented) demo app: frontend -> backend, plus a
# load generator.
set -euo pipefail
cd "$(dirname "$0")/.."

docker build --build-arg SERVICE=frontend -t obi-demo/frontend:v1 app/
docker build --build-arg SERVICE=backend -t obi-demo/backend:v1 app/

# The only images that need side-loading: they exist nowhere but this machine.
kind load docker-image obi-demo/frontend:v1 obi-demo/backend:v1 --name obi-demo

kubectl --context kind-obi-demo apply -f k8s/demo-app.yaml
kubectl --context kind-obi-demo -n demo rollout status deploy/backend deploy/frontend deploy/loadgen --timeout=180s

echo
echo "Demo app is up and taking traffic. Note: zero instrumentation on board."
