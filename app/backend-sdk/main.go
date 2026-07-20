// backend-sdk is the same quote service, now instrumented with the OpenTelemetry
// Go SDK. It adds what eBPF cannot see from the kernel: a custom child span
// around the business logic, carrying a business attribute.
//
// Exporter configuration comes entirely from standard env vars
// (OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME) set in the Deployment.
package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func main() {
	ctx := context.Background()
	exporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		log.Fatalf("otlp exporter: %v", err)
	}
	tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exporter))
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.TraceContext{})

	tracer := otel.Tracer("quote-service")

	quote := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// This span is the payoff of SDK instrumentation: business logic,
		// named and attributed in domain terms. No eBPF probe can produce it.
		_, span := tracer.Start(r.Context(), "calculate-quote")
		defer span.End()

		// Attribute the span before the failure branch, so even failing
		// requests carry the business context you'd want when debugging them.
		price := 1 + rand.Float64()*99
		span.SetAttributes(attribute.Float64("quote.price_usd", price))

		time.Sleep(time.Duration(5+rand.Intn(115)) * time.Millisecond)
		if rand.Intn(100) < 5 {
			http.Error(w, "quote service overloaded", http.StatusInternalServerError)
			return
		}
		fmt.Fprintf(w, `{"price_usd":%.2f}`, price)
	})

	// otelhttp gives us the server span and joins the incoming trace context.
	http.Handle("/api/quote", otelhttp.NewHandler(quote, "GET /api/quote"))

	log.Println("backend (SDK-instrumented) listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
