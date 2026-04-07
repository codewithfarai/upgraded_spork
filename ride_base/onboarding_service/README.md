# Onboarding Service

Onboarding Service for RideBase.

## Database Migrations (Alembic)

Use this flow whenever you change SQLAlchemy models (for example, adding a new column).

### 1. Make your model change

Edit the relevant model under `app/models/`.

### 2. Generate the migration

```bash
make migrate m="describe_your_change"
```

This single command:
- Spins up a temporary local Postgres container
- Applies all existing migrations to it (so it reflects the current prod schema)
- Runs `alembic revision --autogenerate` to diff your models and generate the delta
- Destroys the temporary container

The new migration file will appear under `migrations/versions/`.

### 3. Review the generated migration

Check the file under `migrations/versions/` and confirm it contains exactly the operations you expect. Autogenerate is not perfect — always review before committing.

### 4. Commit and deploy

Commit the migration file alongside your model changes, build and push the image, then run the Ansible playbook. Ansible will automatically apply `alembic upgrade head` inside the new container against the real database.

## Deployment Behavior (Ansible)

During deployment, Ansible runs Alembic in a one-off container:

```bash
alembic upgrade head
```

`DATABASE_URL` is injected at runtime from deployment secrets. The migration step is serialized with a host lock and retryable, so reruns after interruptions are safe.

## Data Model

### UserProfile
The `user_profiles` table now uses a **Dual-Role** system instead of a single Enum:
- **`is_rider`**: Defaults to `True`. Everyone starts as a Rider.
- **`is_driver`**: Defaults to `False`. Becomes `True` only after Step 3 (Vehicle Setup) is confirmed.
- **`role_intent`**: Stores the user's initial signup choice (`RIDER` or `DRIVER`) to guide the app flow.
- **`created_at` / `updated_at`**: Automated UTC timestamps for all profile events.

### DriverDetails
Stores vehicle and identification metadata. Linked via `profile_id` to `user_profiles`.
- **Timestamps**: Now includes `created_at` and `updated_at` for vehicle confirmation auditing.
