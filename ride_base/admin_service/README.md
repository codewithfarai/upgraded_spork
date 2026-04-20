# Admin / Fleet Management Service

Fleet Management Service for RideBase. Handles vehicle registration, driver-to-vehicle assignments, and invite-based driver onboarding for fleet owners.

## API Endpoints

All endpoints require a valid Authentik JWT (Bearer token) and are prefixed with `/api/v1/fleet`.

### Vehicles

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/vehicles` | Register a new vehicle under the current user's fleet |
| `GET` | `/vehicles` | List all vehicles owned by the current user |
| `POST` | `/vehicles/self_assign` | Register a vehicle AND assign it to yourself (owner-operator) |

### Assignments

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/vehicles/{vehicle_id}/assign` | Assign a vehicle to a driver (by driver_id) |
| `DELETE` | `/vehicles/{vehicle_id}/assign` | Revoke the active driver from a vehicle |

### Invites

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/vehicles/{vehicle_id}/invite` | Generate a shareable invite token (expires in 7 days) |
| `POST` | `/vehicles/accept_invite` | Accept an invite token and get assigned to the vehicle |

## RabbitMQ Events

The service publishes the following events to the `ridebase.events` exchange:

| Routing Key | Trigger |
|-------------|---------|
| `fleet.vehicle_registered` | A new vehicle is added to the platform |
| `fleet.driver_assigned` | A driver is linked to a vehicle |
| `fleet.driver_unassigned` | A fleet owner revokes a driver |
| `fleet.invite_generated` | An invite token is created |
| `fleet.invite_accepted` | A driver accepts an invite |

## Database Migrations (Alembic)

Use this flow whenever you change SQLAlchemy models.

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

### Vehicle
The `vehicles` table stores all registered vehicles on the platform.
- **`owner_id`**: Authentik UUID of the fleet owner who registered this vehicle.
- **`car_make` / `car_model` / `car_colour` / `year` / `license_plate`**: Vehicle identification.
- **`registration_document_url`**: Optional S3 link to uploaded registration documents.
- **`created_at` / `updated_at`**: Automated UTC timestamps.

### VehicleAssignment
The `vehicle_assignments` table maps drivers to vehicles.
- **`vehicle_id`**: FK to `vehicles`.
- **`driver_id`**: Authentik UUID of the assigned driver.
- **`status`**: `ACTIVE`, `INACTIVE`, or `REVOKED`.
- **`created_at` / `updated_at`**: Automated UTC timestamps.

### VehicleInvite
The `vehicle_invites` table stores single-use invite tokens.
- **`token`**: Cryptographically secure URL-safe string (32 bytes).
- **`vehicle_id`**: FK to `vehicles`.
- **`owner_id`**: Authentik UUID of the fleet owner who generated the invite.
- **`is_used`**: Boolean flag — burned after acceptance.
- **`expires_at`**: Invite expiration (default: 7 days from creation).

## Docker

```bash
# Build and push multi-platform image
make build
```
