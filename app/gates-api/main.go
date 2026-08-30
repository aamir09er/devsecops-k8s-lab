package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

const listenAddr = ":8080"

type healthResponse struct {
	Status string `json:"status"`
}

type readyResponse struct {
	Ready            bool `json:"ready"`
	SecretConfigured bool `json:"secret_configured"`
}

func secretConfigured() bool {
	return os.Getenv("DATABASE_PASSWORD") != ""
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("write json: %v", err)
	}
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"service": "gates-api",
			"message": "gates-api running",
		})
	})

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{Status: "healthy"})
	})

	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, _ *http.Request) {
		configured := secretConfigured()
		status := http.StatusOK
		if !configured {
			status = http.StatusServiceUnavailable
		}
		writeJSON(w, status, readyResponse{
			Ready:            configured,
			SecretConfigured: configured,
		})
	})

	log.Printf("gates-api listening on %s", listenAddr)
	if err := http.ListenAndServe(listenAddr, mux); err != nil {
		log.Fatal(err)
	}
}
