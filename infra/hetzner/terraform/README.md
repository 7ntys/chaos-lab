# Hetzner Terraform (cx23 Germany)

This stack creates one Hetzner Cloud server with:

- Server type: `cx23`
- Location: `nbg1` (Germany)
- SSH key loaded from `~/.ssh/id_rsa.pub`
- Firewall allowing inbound `tcp/22` and `tcp/80`

Defaults:
- `ssh_source_cidr = "0.0.0.0/0"` (restrict to your IP in production)
- `http_source_cidr = "0.0.0.0/0"`

## Usage

```bash
cd infra/hetzner/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set hcloud_token

terraform init
terraform plan
terraform apply
```

After apply:

```bash
terraform output ssh_command
terraform output app_url
```

## One-command flow from repo root

```bash
make up
make down
```
