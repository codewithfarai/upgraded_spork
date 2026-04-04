"""initial_onboarding_schema

Revision ID: 105bc75c0073
Revises:
Create Date: 2026-04-04 14:26:37.117180

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '105bc75c0073'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    role_enum = sa.Enum("RIDER", "DRIVER", name="roleenum")
    role_enum.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "user_profiles",
        sa.Column("authentik_user_id", sa.String(), nullable=False),
        sa.Column("full_name", sa.String(), nullable=False),
        sa.Column("phone_number", sa.String(), nullable=False),
        sa.Column("city", sa.String(), nullable=False),
        sa.Column("role", role_enum, nullable=False),
        sa.PrimaryKeyConstraint("authentik_user_id"),
    )
    op.create_index(
        "ix_user_profiles_authentik_user_id",
        "user_profiles",
        ["authentik_user_id"],
        unique=False,
    )

    op.create_table(
        "driver_details",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("profile_id", sa.String(), nullable=False),
        sa.Column("car_make", sa.String(), nullable=False),
        sa.Column("car_model", sa.String(), nullable=False),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("license_plate", sa.String(), nullable=False),
        sa.Column("driver_license_number", sa.String(), nullable=False),
        sa.Column("driver_license_photo_url", sa.String(), nullable=False),
        sa.Column("is_available_now", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["user_profiles.authentik_user_id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("profile_id"),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table("driver_details")
    op.drop_index("ix_user_profiles_authentik_user_id", table_name="user_profiles")
    op.drop_table("user_profiles")
    sa.Enum("RIDER", "DRIVER", name="roleenum").drop(op.get_bind(), checkfirst=True)
