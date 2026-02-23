# Chaos Scenarios (Hetzner VM)

This folder contains inject/heal scripts used by `make chaos`.

Each scenario script supports:

- `inject`: apply the failure.
- `heal`: rollback the failure.
- `meta`: print scenario metadata (`id`, `difficulty`, `layer`, ...).

The launcher (`infra/hetzner/run_chaos.sh`) picks one scenario at random and runs it over SSH on your VM.
It also prints a user-facing incident ticket based on `tickets/CH-xxx.txt`.

## Available layers

- app
- db
- lb
- network
- os
- kernel

## Safety

- Scenarios are designed to be reversible with `make chaos-heal`.
- Tickets are stored in `.chaos-tickets/` to track and heal the last injected scenario.
- User ticket templates are stored in `chaos/tickets/`.
- Internet-facing safeguards: scenarios avoid direct firewall/INPUT changes on host TCP 22 and TCP 80.
