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
make ssh ENV=dev
```

### 4. GitHub Actions CI Secrets
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

### 5. Clearing Known Hosts
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

### 5. Infrastructure Deployment

---

## Pre-Commit Hooks

All commits are checked by [pre-commit](https://pre-commit.com/). Hooks run automatically on `git commit`, or trigger manually:

```bash
poetry run pre-commit run --all-files
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
