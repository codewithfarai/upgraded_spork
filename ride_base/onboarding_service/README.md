# Onboarding Service

Onboarding Service for RideBase.

## Database Migrations (Alembic)

Use this flow whenever you change SQLAlchemy models (for example, adding a new column).

This service uses deployment-driven migrations. You do not need to run Alembic locally.

### 1. Make your model change

Example: add a new column in one of the models under `app/models/`.

### 2. Create a migration file

Generate a new revision file in the service project:

```bash
poetry run alembic revision -m "add_<column_name>_to_<table_name>"
```

Notes:

- This creates a migration scaffold under `migrations/versions/`.
- Add explicit `op.add_column(...)`, `op.create_index(...)`, etc. in `upgrade()` and the reverse in `downgrade()`.
- Keep migrations transactional/idempotent where possible.

### 3. Review the generated migration

Check the file under `migrations/versions/` and confirm it contains exactly the operations you expect.

### 4. Deploy

Run your normal deployment pipeline/playbook. During deploy, Ansible runs migrations for you.

## Deployment Behavior (Ansible)

In deployment, Ansible runs Alembic in a one-off container:

```bash
alembic upgrade head
```

`DATABASE_URL` is injected at runtime by Ansible from deployment secrets/variables.

The migration task is configured to be retryable and serialized with a host lock, so reruns after interruptions are safe.
