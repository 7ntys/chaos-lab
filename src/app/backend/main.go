package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

type menuItem struct {
	ID          int    `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Category    string `json:"category"`
	PriceCents  int    `json:"price_cents"`
}

type special struct {
	ID          int    `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
}

func main() {
	addr := envOrDefault("APP_ADDR", ":8080")
	databaseURL := envOrDefault("DATABASE_URL", "postgres://cafe:cafe@db:5432/cafe?sslmode=disable")

	db, err := openDBWithRetry(databaseURL, 20, 2*time.Second)
	if err != nil {
		log.Fatalf("database startup failed: %v", err)
	}
	defer db.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler(db))
	mux.HandleFunc("/api/menu", menuHandler(db))
	mux.HandleFunc("/api/specials", specialsHandler(db))

	server := &http.Server{
		Addr:              addr,
		Handler:           withLogging(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
	}

	log.Printf("backend listening on %s", addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("http server failed: %v", err)
	}
}

func openDBWithRetry(dsn string, maxTries int, wait time.Duration) (*sql.DB, error) {
	var lastErr error

	for i := 1; i <= maxTries; i++ {
		db, err := sql.Open("postgres", dsn)
		if err != nil {
			lastErr = err
			time.Sleep(wait)
			continue
		}

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		err = db.PingContext(ctx)
		cancel()
		if err == nil {
			return db, nil
		}

		_ = db.Close()
		lastErr = err
		log.Printf("database not ready (%d/%d): %v", i, maxTries, err)
		time.Sleep(wait)
	}

	return nil, fmt.Errorf("database unavailable after %d tries: %w", maxTries, lastErr)
}

func healthHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		if err := db.PingContext(ctx); err != nil {
			http.Error(w, "db unavailable", http.StatusServiceUnavailable)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	}
}

func menuHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		rows, err := db.QueryContext(ctx, `
			SELECT id, name, description, category, price_cents
			FROM menu_items
			ORDER BY id
		`)
		if err != nil {
			http.Error(w, "failed to load menu", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		items := make([]menuItem, 0, 16)
		for rows.Next() {
			var item menuItem
			if err := rows.Scan(&item.ID, &item.Name, &item.Description, &item.Category, &item.PriceCents); err != nil {
				http.Error(w, "failed to read menu", http.StatusInternalServerError)
				return
			}
			items = append(items, item)
		}
		if err := rows.Err(); err != nil {
			http.Error(w, "failed to stream menu", http.StatusInternalServerError)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

func specialsHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		rows, err := db.QueryContext(ctx, `
			SELECT id, title, description
			FROM specials
			ORDER BY id
		`)
		if err != nil {
			http.Error(w, "failed to load specials", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		items := make([]special, 0, 8)
		for rows.Next() {
			var item special
			if err := rows.Scan(&item.ID, &item.Title, &item.Description); err != nil {
				http.Error(w, "failed to read specials", http.StatusInternalServerError)
				return
			}
			items = append(items, item)
		}
		if err := rows.Err(); err != nil {
			http.Error(w, "failed to stream specials", http.StatusInternalServerError)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{"specials": items})
	}
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("json encode error: %v", err)
	}
}

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(start))
	})
}

func envOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
