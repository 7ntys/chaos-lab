SHELL := /bin/bash

TF_DIR := infra/hetzner/terraform
DEPLOY_SCRIPT := infra/hetzner/deploy_app.sh
CHAOS_SCRIPT := infra/hetzner/run_chaos.sh
CHAOS_GOAL_DIFFICULTY := $(filter easy medium hard,$(MAKECMDGOALS))
CHAOS_SELECTED_DIFFICULTY := $(if $(DIFFICULTY),$(DIFFICULTY),$(if $(CHAOS_DIFFICULTY),$(CHAOS_DIFFICULTY),$(firstword $(CHAOS_GOAL_DIFFICULTY))))

.PHONY: up infra-up deploy down infra-down ip app-url chaos chaos-list chaos-heal chaos-heal-all easy medium hard

up: infra-up deploy

infra-up:
	terraform -chdir=$(TF_DIR) init -input=false
	terraform -chdir=$(TF_DIR) apply -auto-approve

deploy:
	$(DEPLOY_SCRIPT)

down: infra-down

infra-down:
	terraform -chdir=$(TF_DIR) destroy -auto-approve

ip:
	terraform -chdir=$(TF_DIR) output -raw server_ipv4

app-url:
	terraform -chdir=$(TF_DIR) output -raw app_url

chaos:
	$(CHAOS_SCRIPT) run $(SCENARIO_ID) $(if $(CHAOS_SELECTED_DIFFICULTY),--difficulty $(CHAOS_SELECTED_DIFFICULTY),)

easy medium hard:
	@:

chaos-list:
	$(CHAOS_SCRIPT) list

chaos-heal:
	$(CHAOS_SCRIPT) heal last

chaos-heal-all:
	$(CHAOS_SCRIPT) heal-all
