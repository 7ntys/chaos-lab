# Chaos Cafe Full App

Stack:
- Frontend: React + Vite
- Backend: Go (read-only API)
- DB: Postgres (seeded data)
- LB: Nginx

Folders:
- `src/app/frontend`: React UI
- `src/app/backend`: Go API
- `src/db`: SQL schema + seed
- `src/lb`: Nginx load balancer config

## Run

```bash
cd src
docker compose up --build
```

Open: `http://localhost:8080`

To expose on port 80:

```bash
LB_PUBLISHED_PORT=80 docker compose up --build
```

## Endpoints

- `GET /healthz`
- `GET /api/menu`
- `GET /api/specials`

All endpoints are read-only (no user input).
