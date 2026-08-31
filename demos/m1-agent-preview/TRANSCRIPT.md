# Transcript: an agent containerizes the stats API

This is a real run, not a mock-up. Every command and every line of output below actually
happened, in this order, against the files in this folder.

## What the agent had

- `SPEC.md`, the intent: containerize `app/`, a Flask app with a Redis-backed counter.
- `.claude/skills/container-conventions/SKILL.md`, the harness: house rules for any
  Dockerfile or compose file in this repo, pinned base images, multi-stage builds,
  non-root users, health checks, named volumes for state, secrets as environment
  variables.

Neither file mentions the other. The skill applies automatically to any containerization
task, the spec only describes this one app.

## What it produced

`Dockerfile`, a two-stage build: a `builder` stage that installs Python dependencies, and
a slim final stage that copies only the installed packages and the app code, runs as
`appuser`, and declares a `HEALTHCHECK` against `/health`.

`docker-compose.yml`, two services. `redis` on a pinned tag with a named volume. `app`
waits on `depends_on: redis: condition: service_healthy`, not just on the container
existing, and gets its Redis connection string from an environment variable rather than a
hardcoded value.

Every rule in the skill shows up somewhere in the two files, not because the spec asked
for it, the spec never mentions non-root users or health checks, but because the skill
applies to every container regardless of what the task description says.

## Verified, for real

```
$ docker compose config --quiet && echo "compose config: valid"
compose config: valid

$ docker compose build
...
Successfully installed Jinja2-3.1.6 MarkupSafe-3.0.3 Werkzeug-3.1.8 blinker-1.9.0 click-8.5.0 flask-3.1.0 itsdangerous-2.2.0 redis-5.2.1
 Image m1-agent-preview-app Built

$ docker compose up -d
 Container m1-agent-preview-redis-1  Started
 Container m1-agent-preview-redis-1  Waiting
 Container m1-agent-preview-redis-1  Healthy
 Container m1-agent-preview-app-1  Started

$ docker compose ps
NAME                       IMAGE                  STATUS                    PORTS
m1-agent-preview-app-1     m1-agent-preview-app   Up 12 seconds (healthy)   0.0.0.0:5000->5000/tcp
m1-agent-preview-redis-1   redis:7.4-alpine       Up 23 seconds (healthy)

$ docker inspect m1-agent-preview-app-1 --format '{{.Config.User}}'
appuser

$ docker compose exec app python3 -c "..." # GET /health
200 {"status":"ok"}

$ docker compose exec app python3 -c "..." # GET /stats, three times
200 {"requests":1}
200 {"requests":2}
200 {"requests":3}
```

Notice the app container did not start until `redis` reported healthy, that's the
`condition: service_healthy` rule doing exactly what it's for. The stats counter went
1, 2, 3, in order, against a real Redis instance, not an in-memory stub. The container
runs as `appuser`, confirmed by `docker inspect`, not just claimed in the Dockerfile.

## What this is a preview of

Nothing here required a human to write a line of Dockerfile or compose syntax by hand.
A spec described the app. A skill described the house rules. An agent produced both files,
and they built, ran, and passed real health checks on the first try. This course teaches
each piece of that separately: Agent Skills, spec-driven infrastructure, and the harness
that enforces conventions like these automatically. Module 1's lab has you run a much
smaller version of the same generate-verify-fix loop, by hand, so that when you see this,
you recognize the shape of it.
