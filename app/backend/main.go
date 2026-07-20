// backend simulates a small "quote service": variable latency and an
// occasional 500, so RED metrics have something to show. Like the frontend,
// it contains zero instrumentation.
package main

import (
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"time"
)

func main() {
	http.HandleFunc("/api/quote", func(w http.ResponseWriter, r *http.Request) {
		// Simulate work: 5-120ms, ~5% errors.
		time.Sleep(time.Duration(5+rand.Intn(115)) * time.Millisecond)
		if rand.Intn(100) < 5 {
			http.Error(w, "quote service overloaded", http.StatusInternalServerError)
			return
		}
		fmt.Fprintf(w, `{"price_usd":%.2f}`, 1+rand.Float64()*99)
	})

	log.Println("backend listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
