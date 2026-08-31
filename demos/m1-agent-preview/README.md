# Preview: an agent, a spec, a skill, a harness

A real, verified example of an agent containerizing a small app against a written spec
and a written Agent Skill, not a mock-up. See `TRANSCRIPT.md` for what actually happened,
with real command output.

This exists as a standalone preview, not wired into any single module yet. Modules 4
(Agent Skills), 7 (Spec-Driven Infrastructure), and 8 (Harness Engineering) each teach one
piece of what's demonstrated here, spec-writing, skill-writing, and the harness that
enforces conventions automatically, so it's parked here until those modules are built,
rather than front-loaded into Module 1's on-ramp before the vocabulary exists.

## Files

```
SPEC.md                                    the intent: containerize this app
.claude/skills/container-conventions/      the harness: house rules for any container in this repo
app/                                       the small Flask + Redis app being containerized
Dockerfile                                 what the agent produced
docker-compose.yml                         what the agent produced
TRANSCRIPT.md                              what actually happened, with real output
```

## Try it yourself

```
docker compose up -d
curl http://localhost:5000/health
curl http://localhost:5000/stats
docker compose down -v
```

## Re-verify

```
./run.sh
```

Exits non-zero on any failed criterion. Run it whenever the pinned versions in
`Dockerfile`, `docker-compose.yml`, or `app/requirements.txt` get bumped, same discipline
as `labs/shared/floci-spike/run.sh`.
