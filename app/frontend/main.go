// frontend is a deliberately basic HTTP service: it receives a request and
// calls the backend. No logging framework, no metrics, no instrumentation.
// Everything you will see in Grafana comes from OBI watching it from the kernel.
package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

func main() {
	client := &http.Client{Timeout: 5 * time.Second}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		resp, err := client.Get("http://backend:8080/api/quote")
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		w.WriteHeader(resp.StatusCode)
		fmt.Fprintf(w, "frontend -> backend: %s\n", body)
	})

	log.Println("frontend listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
