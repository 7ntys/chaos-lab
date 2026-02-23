# Chaos Cafe Lab

Chaos engineering lab for **System Engineer / SRE interview prep**.

This project provisions a Hetzner VM with Terraform, deploys a full web app stack
(React + Go + Postgres + Nginx), and lets you inject realistic incidents with
one command.

## Features

- Terraform infrastructure on Hetzner (`cx23`, Germany `nbg1`)
- Firewall managed by Terraform (`tcp/22` and `tcp/80`)
- Full demo app stack deployed on VM with Docker Compose
- Random chaos scenarios across app, DB, LB, network, OS, and kernel layers
- Customer-style incident tickets generated per scenario
- One-command lifecycle via `make up`, `make chaos`, `make down`

## Architecture

```text
Internet
   |
   v
Hetzner VM (Ubuntu)
   |
   +-- Nginx LB (port 80)
         |-- React frontend
         |-- Go backend API
         |-- Postgres database

Chaos runner (local -> SSH) injects incidents on the VM
```

## Repository Layout

```text
infra/hetzner/terraform/   # Terraform stack (server + firewall + outputs)
infra/hetzner/deploy_app.sh
infra/hetzner/run_chaos.sh # Chaos orchestrator (run/list/heal/heal-all)

src/                       # App stack (frontend/backend/db/lb)
chaos/scenarios/           # Failure scripts
chaos/tickets/             # User-facing ticket templates per scenario
```

## Prerequisites

- `terraform` >= 1.6
- `make`
- `ssh` client
- SSH key pair at:
  - public key: `~/.ssh/id_rsa.pub`
  - private key: `~/.ssh/id_rsa`
- Hetzner API token

Optional for local app run:
- Docker + Docker Compose

## Quick Start

1. Set your Hetzner token as an environment variable (recommended):

```bash
export TF_VAR_hcloud_token="<your_hetzner_token>"
```

2. Provision infra + deploy app:

```bash
make up
```

3. Check outputs:

```bash
make ip
make app-url
```

4. Destroy everything when done:

```bash
make down
```

## Chaos Workflow

List available scenarios:

```bash
make chaos-list
```

Inject a random incident:

```bash
make chaos
```

Inject a random incident for one difficulty only:

```bash
make chaos easy
# or
make chaos medium
# or
make chaos hard
```

Legacy syntax still works:

```bash
make chaos DIFFICULTY=easy
```

Inject a specific incident:

```bash
make chaos SCENARIO_ID=CH-004
```

You can also use the raw script flag:

```bash
infra/hetzner/run_chaos.sh run --difficulty easy
```

Heal latest incident:

```bash
make chaos-heal
```

Heal all tracked incidents:

```bash
make chaos-heal-all
```

When a scenario launches, the tool prints:
- scenario ID
- difficulty
- layer
- technical ticket ID
- user-facing incident ticket/context

Tickets are stored in `.chaos-tickets/`.

## Scenario Catalog

| ID     | Difficulty | Layer   | Description |
|--------|------------|---------|-------------|
| CH-001 | easy       | app     | Stop backend container |
| CH-002 | easy       | db      | Stop Postgres container |
| CH-003 | medium     | lb      | Break Nginx upstream |
| CH-004 | medium     | network | Block backend -> DB traffic |
| CH-005 | medium     | os      | Fill disk space under `/var/tmp` |
| CH-006 | easy       | os      | CPU saturation (busy loops) |
| CH-007 | hard       | network | DNS blackhole via iptables |
| CH-008 | hard       | kernel  | Reduce TCP backlog sysctls |
| CH-009 | hard       | kernel  | Add netem latency/loss on `docker0` |
| CH-010 | medium     | app     | Break backend DB DSN in compose config |
| CH-011 | hard       | db      | Hold ACCESS EXCLUSIVE lock on `menu_items` |
| CH-012 | medium     | lb      | Add strict Nginx API rate limit |
| CH-013 | hard       | network | Random packet loss to backend on port 8080 |
| CH-014 | medium     | os      | I/O saturation loops on `/var/tmp` |
| CH-015 | hard       | os      | Lower backend `nofile` limit to 64 |
| CH-016 | hard       | kernel  | CPU cgroup throttling on backend container |

## Security and Secrets

The repo is configured to avoid committing sensitive/generated files:
- `**/terraform.tfvars`
- `**/*.tfstate*`
- `.chaos-tickets/`
- `**/node_modules/`
- `**/dist/`

Recommended practices:
- Prefer `TF_VAR_hcloud_token` env var over storing tokens in files.
- Restrict `ssh_source_cidr` and `http_source_cidr` in Terraform for real usage.
- Rotate credentials immediately if accidentally exposed.

## Local App Only (No Terraform)

```bash
cd src
docker compose up --build
```

App will be available on `http://localhost:8080`.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests/checks when relevant
4. Open a PR with clear reproduction and rollback notes for chaos changes

## License

MIT - see `LICENSE`.
