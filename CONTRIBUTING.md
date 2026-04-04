# Contributing

## Development Setup

### Prerequisites

Install the following tools before working on this project.

---

#### Poetry

```bash
curl -sSL https://install.python-poetry.org | python3 -
export PATH="$HOME/.local/bin:$PATH"  # add to ~/.zshrc or ~/.bashrc
poetry --version  # verify
```

#### Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -version  # verify
```

#### tflint

```bash
brew install tflint
tflint --version  # verify
```

#### trivy

```bash
brew install aquasecurity/trivy/trivy
trivy --version  # verify
```

#### Make

Required to use the automated `Makefile` workflow for Terraform commands.

```bash
brew install make
```

---

## Project Setup

**1. Install Python dependencies and create the in-project virtualenv:**

```bash
poetry install
```

**2. Environment setup and AWS credentials:**

Terraform requires AWS credentials to access remote state. Two options:

**Option A — Makefile (Recommended)**

Copy the env template and populate your keys:

```bash
cp terraform/.env.template terraform/.env  # first time only
```

Then use `make` from the `terraform/` directory. All commands support the `ENV` variable (`dev`, `stage`, `prod`).

```bash
cd terraform

# 1. Initialize (must run when switching ENV)
make init ENV=dev

# 2. Plan changes
make plan ENV=dev

# 3. Apply changes (deploys infrastructure)
make apply ENV=dev

# 4. Destroy an environment
make destroy ENV=dev

# 5. Destroy ALL environments (dev, stage, prod)
make destroy_all

# 6. Run linting and static analysis
make lint

# 7. Verify security hardening and NAT connectivity
make verify ENV=dev SSH_KEY=~/.ssh/your_private_key
```

> **Important**: You must run `make init ENV=<name>` whenever switching environments to ensure the correct state file is loaded.

**Option B — Manual export**

```bash
export AWS_ACCESS_KEY_ID=<YOUR_AWS_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<YOUR_AWS_SECRET_ACCESS_KEY>

cd terraform
terraform init
terraform plan
```

**3. Setup pre-commit:**
   ```bash
   poetry run pre-commit install
   ```

### 3. SSH Key Infrastructure
For security and isolation, this project uses unique SSH keys for each environment. You can generate these automatically:

1. **Check Project Name**: Ensure your `project_name` is set in `terraform/terraform.tfvars`.
2. **Generate Keys**: Run the following command:
   ```bash
   cd terraform
   make setup_keys
   ```
3. **Update TerraformVars**: Copy the HCL block printed by the script into your `terraform/terraform.tfvars`.

To verify your keys on disk:
```bash
cd terraform
make view_keys
```

This will list all `project_name_*` keys in your `~/.ssh/` directory.

To quickly jump into the active environment's Bastion host:
```bash
cd terraform
make ssh_bastion ENV=dev
```

You can also use proxy commands to directly connect to cluster nodes through the bastion:

```bash
cd terraform
make ssh_manager ENV=dev
# or
make ssh_worker ENV=dev
```

> **Security Note**: Direct `root` SSH access is disabled. You connect as the `provision` user, and administrative tasks use `sudo`.

### 4. Trusting Host Keys (Security)
For security, this project enforces **Strict Host Key Checking**. You must trust the host keys of your new servers before running any automated tools (like Ansible).

Once your infrastructure is successfully deployed (`make apply`), run:
```bash
cd terraform
make keyscan ENV=dev
```
This utility uses the Bastion host to safely grab the fingerprints of all internal nodes and adds them to your local `~/.ssh/known_hosts`.

> **Note**: You only need to run this once per deployment, or after using `make ssh_cleanup`.

### 5. DNS Zone Setup (One-Time)

Before deploying any environment, the DNS zone must exist in Hetzner Cloud. This only needs to be done **once per domain**.

1. **Ensure `domain_name` is set** in `terraform/terraform.tfvars`:
   ```hcl
   domain_name = "ridebase.tech"
   ```

2. **Create the zone**:
   ```bash
   cd terraform
   make setup-dns
   ```

3. **Copy the nameservers** printed in the terminal output and paste them into your domain registrar (e.g. GoDaddy) under **Custom Nameservers**:
   ```
   hydrogen.ns.hetzner.com.
   oxygen.ns.hetzner.com.
   helium.ns.hetzner.de.
   ```

> **How it works**: Each `make apply ENV=<name>` automatically creates an A record pointing to that environment's Load Balancer:
> - `make apply ENV=dev` → `dev.ridebase.tech`
> - `make apply ENV=stage` → `stage.ridebase.tech`
> - `make apply ENV=prod` → `ridebase.tech` (root domain)

### 5. GitHub Actions CI Secrets
The GitHub Actions workflow requires your local environment variables and Hetzner Token to function. You can automate syncing these secrets to your repository using the GitHub CLI (`gh`):

1. **Install GitHub CLI**: `brew install gh` (macOS)
2. **Login**: `gh auth login`
3. **Sync Secrets**:
   ```bash
   cd terraform
   make sync_secrets
   ```

This will automatically:
1. Push `TF_STATE_BUCKET`, `TF_STATE_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `TF_VAR_project_name` to your **Repository Variables**.
2. Push `HCLOUD_TOKEN` to your **Repository Secrets**.
3. Create `dev`, `stage`, and `prod` **GitHub Environments** and push the isolated `TF_VAR_ssh_key` into each environment securely.

### 7. Deployment Flow Summary
For a successful deployment, you **must** follow this exact 3-phase sequence to resolve the "Chicken-and-Egg" dependency between the infrastructure, the applications, and the SSO provider (Authentik).

1.  **Phase 1: Cloud Infrastructure (Terraform)**
    ```bash
    cd terraform
    make apply ENV=dev
    make keyscan ENV=dev  # Critical for Ansible to connect
    ```
    *Result*: VMs, VPC, and Firewall are provisioned.

2.  **Phase 2: Application Stack (Ansible + Docker Swarm)**
    ```bash
    cd ../ansible
    make swarm ENV=dev
    ```
    *Result*: Docker Swarm is initialized and all apps (Traefik, Authentik, Monitoring) are deployed.
    *Crucial*: This phase generates a random Authentik API token and **automatically copies it back** to `terraform_authentik/terraform.tfvars`.

3.  **Phase 3: SSO Integration (Terraform Authentik)**
    ```bash
    cd ../terraform_authentik
    make apply ENV=dev
    ```
    *Result*: This finalized the setup by creating the OIDC Providers, Applications (Grafana, etc.), and Outpost bindings using the token generated in Phase 2.

### 8. Clearing Known Hosts
When destroying and recreating infrastructure, your local `~/.ssh/known_hosts` will contain outdated fingerprings for the recycled IPs.

To surgically remove only the IPs associated with the current project environment:
```bash
cd terraform
make ssh_cleanup
```

To clear **all** host records (start fresh):
```bash
# Backup and clear
cp ~/.ssh/known_hosts ~/.ssh/known_hosts.bak && > ~/.ssh/known_hosts
```

### 9. Docker Swarm Deployment (Ansible)

After infrastructure is deployed and keys are scanned (`make apply` -> `make keyscan`), bootstrap Docker Swarm:

1. **Ensure dependencies are installed** (Ansible is included in the project's Poetry dependencies):
   ```bash
   poetry install
   ```

2. **Bootstrap Docker Swarm** for an environment:
   ```bash
   cd ansible
   make swarm ENV=dev
   ```

   This will:
   - Install Docker CE on all nodes (managers, workers, edge, database)
   - Initialize Docker Swarm on the primary manager
   - Join all other managers and workers to the cluster
   - Apply role labels (`edge`, `database`, `worker`) to nodes
   - Drain manager nodes (managers only orchestrate, not run workloads)

3. **Dry-run** (check mode, no changes made):
   ```bash
   make swarm_check ENV=dev
   ```

4. **Verify** the cluster by SSH'ing into a manager:
   ```bash
   make ssh_manager ENV=dev
   docker node ls
   ```
---

## Pre-Commit Hooks

All commits are checked by [pre-commit](https://pre-commit.com/). Hooks run automatically on `git commit`, or trigger manually:

```bash
poetry run pre-commit run --all-files
```

To test commit scope validation locally with a custom commit message:

```bash
# Stage files first, then run:
make test-commit-scope MSG='feat(payment): add webhook idempotency guard'
```

| Hook | What it does |
|---|---|
| `trailing-whitespace` | Strips trailing whitespace |
| `end-of-file-fixer` | Ensures files end with a newline |
| `check-yaml` / `check-toml` | Validates YAML and TOML syntax |
| `detect-private-key` | Blocks accidental secret commits |
| `commitizen` | Enforces conventional commit messages |
| `terraform_fmt` | Auto-formats Terraform files |
| `terraform_validate` | Validates Terraform configuration |
| `terraform_tflint` | Lints Terraform for best practice violations |
| `terraform_trivy` | Scans Terraform for security misconfigurations |

---

## Commit Convention

This project follows [Conventional Commits](https://www.conventionalcommits.org/).

Valid types: `feat` · `fix` · `perf` · `build` · `refactor` · `test` · `style` · `chore` · `docs` · `ci`

For service changes, use scoped commit tags so version bumps and changelogs are routed correctly:

- Payment service: `type(payment): message`
- Onboarding service: `type(onboarding): message`
- Root/shared infra changes: `type(infra): message` (or `type(root): message`)

Scope enforcement is path-aware during `commit-msg`:

- Changes only under `ride_base/payment_service/` require `(payment)`
- Changes only under `ride_base/onboarding_service/` require `(onboarding)`
- Changes touching both services in one commit require `(infra)` or `(root)`

Examples:

- `feat(payment): add webhook idempotency guard`
- `fix(onboarding): validate OIDC subject mapping`
- `chore(infra): align shared event contracts`

---

## Versioning Model

This repository uses three independent semantic version tracks:

- Root platform (`pyproject.toml`, tag format `vX.Y.Z`)
- Payment service (`ride_base/payment_service/pyproject.toml`, tag format `payment_service-vX.Y.Z`)
- Onboarding service (`ride_base/onboarding_service/pyproject.toml`, tag format `onboarding_service-vX.Y.Z`)

Each track bumps only when its paths change in CI:

- Root bump: any changes outside both service folders
- Payment bump: changes under `ride_base/payment_service/`
- Onboarding bump: changes under `ride_base/onboarding_service/`

CI also requires matching commit message scopes before bumping:

- Root bump requires `type(infra): ...` or `type(root): ...`
- Payment bump requires `type(payment): ...`
- Onboarding bump requires `type(onboarding): ...`

If path changes exist without matching scope/type commits, that track is skipped (no empty bump release).

For each service bump, Commitizen updates all three targets together:

- `tool.poetry.version`
- `tool.commitizen.version`
- `app/__init__.py` `__version__`
