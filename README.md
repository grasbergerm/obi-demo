# Zero-Code Observability on Kubernetes with OBI

Companion demo for the article *"Zero-Code Observability on Kubernetes: What
OpenTelemetry's eBPF Instrumentation Actually Gives You (and What It Doesn't)"*.

It runs [OpenTelemetry eBPF Instrumentation (OBI)](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation)
(formerly Grafana Beyla) on a local [kind](https://kind.sigs.k8s.io/) cluster and shows:

1. **Zero-code**: RED metrics (rate, errors, duration), traces, and a service
   graph for a completely uninstrumented Go app, no env vars, sidecars, image
   rebuilds, or restarts.
2. **Hybrid**: one service switched to the OTel SDK; OBI detects it and stops
   emitting its own traces for that service, so nothing is double-counted.

## What gets deployed

```
┌─ namespace: demo ──────────────────────────────┐
│  loadgen ──> frontend ──> backend              │   plain Go, zero
│              (:8080)      (:8080, /api/quote)  │   instrumentation
└────────────────────────────────────────────────┘
┌─ namespace: obi ───────────────────────────────┐
│  OBI DaemonSet (privileged, hostPID)           │   eBPF probes in the
│  discovery: k8s_namespace=demo                 │   node's kernel
└────────────────────────────────────────────────┘
┌─ namespace: observability ─────────────────────┐
│  grafana/otel-lgtm all-in-one                  │   OTLP in :4317,
│  Grafana + Tempo + Prometheus + Loki           │   Grafana out :3000
└────────────────────────────────────────────────┘
```

`backend` answers with variable latency and ~5% errors so the dashboards have
something to show.

## Prerequisites

- `docker`, `kind`, `kubectl`, `helm` (and `jq` for `scripts/verify.sh`)
- ~4 GB free RAM
- A kernel with BTF, uprobes, and tracefs. Both Docker Desktop and stock
  Linux distro kernels qualify. Verify: `ls /sys/kernel/btf/vmlinux` must exist.

## Walkthrough

For a guided run of everything below in one command:

```bash
./scripts/demo.sh
```

Or step by step:

### Phase 1: zero-code

```bash
./scripts/01-cluster.sh         # kind cluster
./scripts/02-observability.sh   # LGTM stack
./scripts/03-app.sh             # uninstrumented app + load generator
./scripts/04-obi.sh             # OBI via Helm  <-- telemetry starts here
```

The entire OBI integration is one Helm release and one values file:
[`obi-values.yaml`](obi-values.yaml).

Give it ~30 seconds, then:

```bash
./scripts/verify.sh   # terminal proof: Tempo traces + Prometheus RED metrics
kubectl --context kind-obi-demo -n observability port-forward svc/lgtm 3000:3000
# Grafana at http://localhost:3000 (admin/admin)
```

Grafana opens straight onto the provisioned demo dashboard: request rate,
error rate, and p95 per service, the service graph, and a clickable list of
failing traces. For raw data, use Explore: Tempo has `GET /api/quote` traces,
Prometheus has `http_server_request_duration_seconds_*` by
service/route/status.

What you *won't* find is anything OBI can't see from the kernel: no
business-logic spans and no custom attributes, which is what phase 2 is for.

### Phase 2: hybrid

```bash
./scripts/05-hybrid.sh
```

Swaps `backend` for an OTel Go SDK build
([`app/backend-sdk/main.go`](app/backend-sdk/main.go)) that adds a custom
`calculate-quote` span, business detail eBPF can't see. OBI notices the
process exporting OTLP and, per `discovery.exclude_otel_instrumented_services`
(default `true`), stops emitting its own traces for it. A minute later:

- `backend` traces come from the SDK (one trace per request, not two).
- `frontend` traces still come from OBI.
- RED and service-graph metrics still cover both services.

Re-run `./scripts/verify.sh`, its last section shows who produces backend's
traces, before and after the switch.

## Repo layout

```
app/frontend/       plain Go HTTP service, calls backend
app/backend/        plain Go "quote service": variable latency, ~5% errors
app/backend-sdk/    same backend + OTel SDK
app/Dockerfile      shared multi-stage build (SERVICE build-arg)
k8s/                LGTM stack, demo app, phase-2 backend, Grafana dashboard
obi-values.yaml     the entire OBI integration
scripts/            demo.sh (guided run), numbered steps, verify.sh
```

## Cleanup

```bash
kind delete cluster --name obi-demo
```

## Troubleshooting

- **OBI pod in `Error`/CrashLoop with `kernel does not support BTF … no vmlinux
  BTF found`** the Docker VM's kernel lacks BTF. On Docker Desktop for Mac
  this is the "Docker VMM" backend: switch Settings → General → Virtual Machine
  Options to "Apple Virtualization Framework", Apply & Restart, then recreate
  the cluster. `demo.sh` checks for this up front.
- **RED metrics empty right after traces appear** OBI exports metrics on an
  interval (10s here, 60s by OBI default); give it a moment or re-run
  `./scripts/verify.sh`.
- **OBI pod fails with `mkdir /sys/kernel/tracing: read-only file system`**
  the kernel lacks tracefs (and likely BTF/uprobes). Run on Docker Desktop or
  a stock Linux host instead.
- **No traces in Tempo** check OBI logs (`kubectl -n obi logs ds/…`) or, in
  phase 2, the SDK backend's logs for OTLP export errors.
