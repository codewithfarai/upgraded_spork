# Load environment variables from .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: init plan apply destroy lint

init:
	terraform init \
		-backend-config="bucket=$(TF_STATE_BUCKET)" \
		-backend-config="key=$(TF_STATE_KEY)"

plan:
	terraform plan

apply:
	terraform apply

destroy:
	terraform destroy

lint:
	poetry run pre-commit run --all-files
