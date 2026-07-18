#!/usr/bin/env bash
# Interactive walkthrough: runs the numbered scripts in order, pausing between
# phases. Nothing here but narration and readiness waits, each step can also
# be run individually.
set -euo pipefail
cd "$(dirname "$0")"

# --- helpers -----------------------------------------------------------------

missing=()
for cmd in docker kind kubectl helm jq curl; do
  command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if ((${#missing[@]})); then
  echo "Missing required tools: ${missing[*]}" >&2
  exit 1
fi

# OBI's eBPF probes need kernel BTF. Fail fast with the fix, not mid-demo.
if ! docker run --rm alpine ls /sys/kernel/btf/vmlinux >/dev/null 2>&1; then
  echo "This Docker environment's kernel has no BTF (/sys/kernel/btf/vmlinux)," >&2
  echo "which OBI requires. On Docker Desktop for Mac this usually means the" >&2
  echo "'Docker VMM' backend: switch Settings > General > Virtual Machine Options" >&2
  echo "to 'Apple Virtualization Framework', Apply & Restart, then re-run." >&2
  exit 1
fi

# Bold narration when on a terminal, so it stands out from kubectl/helm output.
if [ -t 1 ]; then bold=$'\033[1m' reset=$'\033[0m'; else bold='' reset=''; fi
say() { printf '%s%s%s\n' "$bold" "$*" "$reset"; }
pause() {
  echo
  read -rp "${bold}>> Press Enter to $1 ${reset}"
  echo
}

# Poll Tempo through a temporary port-forward until a TraceQL query matches,
# so the demo moves on as soon as the telemetry actually exists. Polling goes
# via the host (not a demo-namespace pod) to stay invisible to OBI.
wait_for_traces() { # $1 = TraceQL query, $2 = what we're waiting for
  say "Waiting for $2 (up to 120s)..."
  kubectl --context kind-obi-demo -n observability port-forward svc/lgtm 13200:3200 >/dev/null 2>&1 &
  local pf=$! deadline=$((SECONDS + 120))
  while ! curl -s -G 'http://localhost:13200/api/search' \
      --data-urlencode "q=$1" --data-urlencode 'limit=1' 2>/dev/null \
      | jq -e '.traces[0]' >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      say "Not there after 120s, continuing; verify.sh below shows the current state."
      break
    fi
    sleep 3
  done
  kill "$pf" 2>/dev/null || true
  wait "$pf" 2>/dev/null || true
}

# Same idea for the first RED metrics: OBI exports them on an interval
# (10s, set in obi-values.yaml), so they land a beat after the traces.
wait_for_metrics() {
  say "Waiting for the first RED metrics (up to 120s)..."
  kubectl --context kind-obi-demo -n observability port-forward svc/lgtm 19090:9090 >/dev/null 2>&1 &
  local pf=$! deadline=$((SECONDS + 120))
  while ! curl -s -G 'http://localhost:19090/api/v1/query' \
      --data-urlencode 'query=http_server_request_duration_seconds_count' 2>/dev/null \
      | jq -e '.data.result[0]' >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      say "Not there after 120s, continuing; verify.sh below shows the current state."
      break
    fi
    sleep 3
  done
  kill "$pf" 2>/dev/null || true
  wait "$pf" 2>/dev/null || true
}

# Long-lived port-forwards for the user (Grafana, the app). Started in the
# background, checked once, and cleaned up when the script exits.
pf_pids=()
port_forward() { # $1 = namespace, $2 = service, $3 = local:remote, $4 = url
  kubectl --context kind-obi-demo -n "$1" port-forward "svc/$2" "$3" >/dev/null 2>&1 &
  pf_pids+=($!)
  sleep 1
  if curl -s -o /dev/null --max-time 3 "$4"; then
    say "$2 is now at $4"
  else
    say "$2 port-forward on $4 didn't come up, is the port already in use?"
  fi
}
cleanup() { ((${#pf_pids[@]})) && kill "${pf_pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT
trap 'echo; say "A step failed. Fix the issue and re-run ./scripts/demo.sh, completed steps are safe to repeat."' ERR

# --- the demo ----------------------------------------------------------------

say "== OBI demo: zero-code observability, then the hybrid handoff =="

pause "create the cluster and observability stack"
./01-cluster.sh
./02-observability.sh
port_forward observability lgtm 3000:3000 http://localhost:3000
say "Log in (admin/admin) and keep it open, the demo dashboard is still empty."

pause "deploy the demo app"
./03-app.sh
echo
say "A request through the app:"
kubectl --context kind-obi-demo -n demo exec deploy/loadgen -- curl -s http://frontend:8080/
port_forward demo frontend 8080:8080 http://localhost:8080
say "Open it in a browser, every refresh is a live request."
echo
say "Can we shell into it? (backend is a scratch image: one static binary, nothing else)"
kubectl --context kind-obi-demo -n demo exec deploy/backend -- sh 2>&1 || true
say "No shell, no agent, nowhere to even put instrumentation."
echo
say "And is it emitting any telemetry? Let's check:"
./verify.sh
echo
say "Empty across the board, that's the 'before' picture."

pause "deploy OBI, telemetry starts here"
./04-obi.sh

wait_for_traces '{resource.service.name="backend"}' "the first traces"
wait_for_metrics
./verify.sh
echo
say "Phase 1 done: traces, RED metrics, service graph, zero app changes,"
say "on a container you can't even shell into. Look at 'spans' above: frontend"
say "and backend in ONE trace, context propagation from the kernel, no SDK."
say "The failing requests are backend's deliberate ~5% errors, the red edge"
say "in Grafana's service graph."
say "Now look at the dashboard again (http://localhost:3000): rate, errors, p95,"
say "the service graph, and failing traces you can click into."

pause "start phase 2: swap backend to an OTel SDK build"
./05-hybrid.sh

wait_for_traces '{resource.service.name="backend" && name="calculate-quote"}' "SDK-produced backend traces"
./verify.sh
echo
say "Phase 2 done: backend traces come from the SDK ('producer' above),"
say "frontend traces still from OBI, nothing double-counted."
say "Grafana (:3000) and the app (:8080) stay reachable until you finish here."
say "Cleanup after:"
echo "  kind delete cluster --name obi-demo"
pause "finish (stops the port-forwards)"
