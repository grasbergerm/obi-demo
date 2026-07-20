#!/usr/bin/env bash
# Terminal-side proof that telemetry is flowing: queries Tempo and Prometheus
# through a temporary port-forward. Requires jq.
set -euo pipefail

kubectl --context kind-obi-demo -n observability port-forward svc/lgtm 13200:3200 19090:9090 >/dev/null 2>&1 &
trap 'kill %1 2>/dev/null' EXIT

# Wait until both endpoints answer through the port-forward (up to 20s).
ready() {
  curl -sf http://localhost:13200/api/echo >/dev/null 2>&1 &&
  curl -sf http://localhost:19090/-/ready >/dev/null 2>&1
}
for _ in $(seq 40); do
  if ready; then break; fi
  sleep 0.5
done

echo "=== Which services are sending traces to Tempo? ==="
echo "    (empty = nothing is emitting traces; a name = that service is being observed)"
SERVICES=$(curl -s 'http://localhost:13200/api/search/tag/service.name/values' \
  | jq -r '.tagValues[]? | (.value // .)')
if [ -z "$SERVICES" ]; then
  echo "  → none: no service has produced a single trace yet"
else
  echo "$SERVICES" | sed 's/^/  → /'
fi

echo
echo "=== How many requests/sec is each service handling? (Prometheus RED metrics) ==="
echo "    (one line per service+HTTP status; empty = no request metrics are being recorded)"
RED=$(curl -s -G 'http://localhost:19090/api/v1/query' \
  --data-urlencode 'query=sum by (service_name, http_response_status_code) (rate(http_server_request_duration_seconds_count[2m]))' \
  | jq -r '.data.result[]? | "  → \(.metric.service_name)  HTTP \(.metric.http_response_status_code)  \((.value[1]|tonumber)*100|round/100) req/s"')
echo "${RED:-  → none: no request-rate metrics exist yet}"

echo
echo "=== Which services are calling which? (Prometheus service graph) ==="
echo "    (each edge is caller → callee with its rate; empty = no call graph discovered)"
EDGES=$(curl -s -G 'http://localhost:19090/api/v1/query' \
  --data-urlencode 'query=sum by (client, server) (rate(traces_service_graph_request_total[2m]))' \
  | jq -r '.data.result[]? | "  → \(.metric.client) calls \(.metric.server)  \((.value[1]|tonumber)*100|round/100) req/s"')
echo "${EDGES:-  → none: no service-to-service edges discovered yet}"

echo
echo "=== Failing requests (Tempo, status=error) ==="
ERRORS=$(curl -s -G 'http://localhost:13200/api/search' \
  --data-urlencode 'q={resource.service.name="backend" && status=error}' \
  --data-urlencode 'limit=3' | jq -r '.traces[]? | .traceID + "  " + (.rootTraceName // "")')
echo "${ERRORS:-(none found)}"

echo
echo "=== Who produces backend's traces? (Tempo) ==="
TRACE_ID=$(curl -s -G 'http://localhost:13200/api/search' \
  --data-urlencode 'q={resource.service.name="backend"}' \
  --data-urlencode 'limit=1' | jq -r '.traces[0].traceID // empty')
if [ -z "$TRACE_ID" ]; then
  echo "No backend traces found. (Expected before OBI is deployed; otherwise wait ~30s and re-run.)"
else
  curl -s "http://localhost:13200/api/traces/$TRACE_ID" | jq -r '
    "producer: " + (([.batches[].resource.attributes[]? | select(.key == "telemetry.distro.name") | .value.stringValue] | first)
                    // ([.batches[].resource.attributes[]? | select(.key == "telemetry.sdk.name") | .value.stringValue] | first)
                    // "unknown"),
    "spans:    " + ([.batches[].scopeSpans[].spans[].name] | join(", ")),
    "business: " + ([.batches[].scopeSpans[].spans[] | select(.name == "calculate-quote")
                     | .attributes[]? | select(.key == "quote.price_usd")
                     | "quote.price_usd=" + (.value.doubleValue // .value.stringValue // (.value | tostring))]
                    | first // "(none, eBPF cannot see inside the app)")'
  echo
  echo "Phase 1: producer is 'opentelemetry-ebpf-instrumentation' (OBI). Phase 2:"
  echo "producer is 'opentelemetry' (the app's own SDK), a 'calculate-quote' span"
  echo "appears, and it carries business data. OBI has backed off."
fi
