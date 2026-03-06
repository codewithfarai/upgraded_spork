# Installing Poetry

This project uses Poetry for dependency and virtualenv management. Follow the steps below to install Poetry and set up the project environment.

1. Install Poetry (recommended — official installer)
```bash
curl -sSL https://install.python-poetry.org | python3 -
```

2. Make sure Poetry is on your PATH (restart shell or add to your shell RC file)
```bash
export PATH="$HOME/.local/bin:$PATH"
# or add the above line to ~/.bashrc, ~/.zshrc, etc.
```

3. Verify installation
```bash
poetry --version
```

4. Install project dependencies and create the in-project virtualenv
This repository uses an in-project virtualenv (see poetry.toml). From the project root:
```bash
poetry install
```

---

## Setting Up Pre-Commit Hooks

This project uses [pre-commit](https://pre-commit.com/) to enforce code quality checks before every commit, including Terraform formatting, validation, security scanning, and conventional commit messages.

### Register the hooks

Run this once after cloning the repo (and after `poetry install`):

```bash
poetry run pre-commit install --install-hooks
```

This writes the hook scripts into `.git/hooks/` so they fire automatically on every `git commit`.

## Run hooks manually

To run all hooks against every file at any time:

```bash
poetry run pre-commit run --all-files
```

To run a specific hook:

```bash
poetry run pre-commit run terraform_fmt
```
