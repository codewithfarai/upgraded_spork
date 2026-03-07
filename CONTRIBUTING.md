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

---

#### Project Setup

1. Environment setup and AWS Keys:
   Create a `.env` file in the `terraform/` directory with your AWS credentials. This is because we use a Makefile to automatically parse the `.env` file and export the keys dynamically before running `terraform` commands without declaring dummy variables in code:

   ```env
   AWS_ACCESS_KEY_ID="your_access_key"
   AWS_SECRET_ACCESS_KEY="your_secret_key"
   ```

2. Run Terraform via the Makefile:
   Navigate to the `terraform/` directory and run commands via `make` so keys are correctly exported:
   ```bash
   make init
   make plan
   ```

3. Install Python dependencies and create the in-project virtualenv:

```bash
poetry install
```

2. Register pre-commit hooks (run once after cloning):

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

`feat` · `fix` · `perf` · `build` · `refactor` · `test` · `style` · `chore` · `docs` · `ci`
