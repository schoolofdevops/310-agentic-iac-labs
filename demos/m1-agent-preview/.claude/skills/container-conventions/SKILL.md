---
name: container-conventions
description: House rules for any Dockerfile or docker-compose.yml written in this repo. Use whenever asked to containerize an app, write a Dockerfile, or write a compose file.
---

# Container conventions

Apply these rules to every Dockerfile and compose file, whether or not the request
mentions them by name. They exist so that every container in this repo behaves the same
way in an incident, regardless of who or what wrote it.

## Dockerfile rules

- **Pin every base image to an exact tag.** Never `:latest`, never a bare major version
  like `:3`. A pinned tag is the only thing that makes a build reproducible six months
  from now.
- **Multi-stage build whenever the language needs a compile or install step.** Install
  and build in one stage, copy only the result into a slim final stage. The final image
  should not contain a package manager cache, build tools, or source that isn't served at
  runtime.
- **Never run as root.** Create a dedicated user, switch to it with `USER`, before the
  final `CMD` or `ENTRYPOINT`.
- **Always declare a `HEALTHCHECK`.** A container that is running but not healthy should
  be visible to `docker ps` and to compose's `depends_on: condition: service_healthy`,
  not just to a human reading logs.

## Compose rules

- **`depends_on` uses `condition: service_healthy`, not a bare service name.** A bare
  dependency only waits for the container to start, not for it to be ready. That
  difference is exactly the kind of race condition this course spends a whole module on
  later.
- **Stateful services get a named volume.** Never let a database or cache write to the
  container's own writable layer, it disappears the moment the container is recreated.
- **`restart: unless-stopped` on every long-running service.** A crash should self-heal
  without paging anyone, an operator's deliberate stop should stay stopped.
- **Secrets and connection strings come in as environment variables, never hardcoded in
  the compose file or the image.** This is the same rule Module 1's lab teaches by hand,
  applied here automatically.

## Why this skill exists

Without it, an agent asked to "containerize this" produces something that runs on the
first try and fails the first real incident: a `:latest` base image that silently changed
under you, a container running as root, a cache with no volume that loses its data on
restart. This skill is the harness catching that class of mistake before the pipeline
ever has to.
