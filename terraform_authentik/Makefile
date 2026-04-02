ENV ?= dev

ifneq (,$(wildcard ./.env))
    include .env
    export
endif

init:
	terraform init -reconfigure -backend-config="bucket=$(TF_STATE_BUCKET)" -backend-config="key=$(TF_STATE_KEY)-authentik-$(ENV)"

plan:
	$(MAKE) init ENV=$(ENV)
	terraform plan -var="environment=$(ENV)" $(ARGS)

apply:
	$(MAKE) init ENV=$(ENV)
	terraform apply -var="environment=$(ENV)" $(ARGS)

destroy:
	$(MAKE) init ENV=$(ENV)
	terraform destroy -var="environment=$(ENV)" $(ARGS)
