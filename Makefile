SHELL := /bin/bash

.PHONY: deploy logs

# Deploy the proxy to the server (VPS_TARGET from .env; override: make deploy -- root@<ip> [remote-dir])
DEPLOY_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))

deploy:
	@chmod +x ./scripts/deploy.sh
	./scripts/deploy.sh $(DEPLOY_ARGS)

# Show the proxy's recent logs on the server
logs:
	ssh "$$(sed -n 's/^VPS_TARGET=//p' .env)" "cd caddy-front && docker compose logs --tail 50"

# Turn trailing CLI arguments passed to deploy into dummy rules
ifneq ($(filter deploy,$(firstword $(MAKECMDGOALS))),)
  $(eval $(DEPLOY_ARGS):;@:)
endif
