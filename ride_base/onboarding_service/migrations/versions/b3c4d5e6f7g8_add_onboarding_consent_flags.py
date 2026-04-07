"""add onboarding consent flags

Revision ID: b3c4d5e6f7g8
Revises: a1b2c3d4e5f6
Create Date: 2026-04-07 21:42:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b3c4d5e6f7g8'
down_revision: Union[str, Sequence[str], None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('user_profiles', sa.Column('location_enabled', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('user_profiles', sa.Column('details_confirmed', sa.Boolean(), nullable=False, server_default='false'))
    # Remove server defaults after backfill
    op.alter_column('user_profiles', 'location_enabled', server_default=None)
    op.alter_column('user_profiles', 'details_confirmed', server_default=None)


def downgrade() -> None:
    op.drop_column('user_profiles', 'details_confirmed')
    op.drop_column('user_profiles', 'location_enabled')
