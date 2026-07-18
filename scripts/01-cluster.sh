#!/usr/bin/env bash
# Create the kind cluster.
set -euo pipefail

if kind get clusters 2>/dev/null | grep -qx obi-demo; then
  read -rp "kind cluster 'obi-demo' already exists. Delete it and start fresh? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    kind delete cluster --name obi-demo
  else
    echo "Aborting, delete it yourself with: kind delete cluster --name obi-demo"
    exit 1
  fi
fi
kind create cluster --name obi-demo --wait 180s
