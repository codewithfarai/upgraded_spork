## Contributing

### Development Setup

#### Prerequisites

Install the following tools before working on this project:

##### Poetry

```bash
curl -sSL https://install.python-poetry.org | python3 -
export PATH="$HOME/.local/bin:$PATH"  # add to ~/.zshrc or ~/.bashrc
poetry --version  # verify
```

##### Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -version  # verify
```

##### tflint

```bash
brew install tflint
tflint --version  # verify
```

##### trivy

```bash
brew install aquasecurity/trivy/trivy
trivy --version  # verify
```

##### Make

Make is required if you want to use the automated `Makefile` workflow for terraform commands.

```bash
brew install make
```

---

#### Project Setup

1. **Install Python dependencies and create the in-project virtualenv:**

```bash
poetry install
```

2. **Environment setup and AWS Keys:**

Terraform requires AWS credentials to access the remote state. You can provide these keys in two ways:

**Option A: Using the Makefile (Recommended)**

If you have `make` installed, you can use the automatic `.env` loading feature. Copy the `.env.template` file to `.env`:

```bash
cp terraform/.env.template terraform/.env  # (first time only)
```

Edit `terraform/.env` and add your actual AWS keys. Then, from the `terraform/` directory, use `make` instead of `terraform` directly:

```bash
cd terraform
make init
make plan
make apply
```

**Option B: Manual Export**

If you prefer not to use `make` or `.env`, you can export the keys directly in your terminal session before running `terraform` commands:

```bash
export AWS_ACCESS_KEY_ID=<YOUR_AWS_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<YOUR_AWS_SECRET_ACCESS_KEY>

cd terraform
terraform init
terraform plan
```

3. **Register pre-commit hooks (run once after cloning):**

```bash
poetry run pre-commit install --install-hooks
```

---

#### Pre-Commit Hooks

All commits are checked by [pre-commit](https://pre-commit.com/). Hooks run automatically on `git commit`, or manually:

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

#### Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Valid types:

`feat` &middot; `fix` &middot; `perf` &middot; `build` &middot; `refactor` &middot; `test` &middot; `style` &middot; `chore` &middot; `docs` &middot; `ci`
