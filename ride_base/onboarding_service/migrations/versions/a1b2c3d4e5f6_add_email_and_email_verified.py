"""add email and email_verified to user_profiles

Revision ID: a1b2c3d4e5f6
Revises: f6d78216210b
Create Date: 2026-04-05 21:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = 'f6d78216210b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('user_profiles', sa.Column('email', sa.String(), nullable=False, server_default=''))
    op.add_column('user_profiles', sa.Column('email_verified', sa.Boolean(), nullable=False, server_default='false'))
    # Remove server defaults after backfill
    op.alter_column('user_profiles', 'email', server_default=None)
    op.alter_column('user_profiles', 'email_verified', server_default=None)


def downgrade() -> None:
    op.drop_column('user_profiles', 'email_verified')
    op.drop_column('user_profiles', 'email')
