# Spec: containerize the stats API

## Intent

Containerize the small Flask app in `app/`. It serves two routes: `GET /health` for a
liveness probe, and `GET /stats` which increments and returns a request counter stored in
Redis. Produce a `Dockerfile` for the app and a `docker-compose.yml` that runs the app
alongside a Redis cache.

## Requirements

- `Dockerfile`
  - Multi-stage build: a `builder` stage that installs Python dependencies, a slim final
    stage that copies only the installed packages and the app code.
  - Base image pinned to an exact tag, never `:latest`.
  - Runs as a non-root user.
  - Declares a `HEALTHCHECK` that calls `GET /health`.
  - Exposes port `5000`.
- `docker-compose.yml`
  - Two services: `app` (built from the `Dockerfile`) and `redis`.
  - `redis` uses a pinned exact image tag, never `:latest`.
  - `app` depends on `redis` being healthy before it starts.
  - `redis` data persists in a named volume.
  - Both services restart automatically unless the operator stops them.
  - The app's Redis connection URL is passed in as an environment variable, not
    hardcoded.

## Out of scope

No Kubernetes manifests. No CI pipeline. No TLS. This is a local `docker compose up`
target only.
