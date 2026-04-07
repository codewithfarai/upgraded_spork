"""convert role enum to dual assignment booleans

Revision ID: c4d5e6f7g8h9
Revises: b3c4d5e6f7g8
Create Date: 2026-04-07 22:09:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'c4d5e6f7g8h9'
down_revision: Union[str, Sequence[str], None] = 'b3c4d5e6f7g8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Add new columns
    op.add_column('user_profiles', sa.Column('is_rider', sa.Boolean(), nullable=False, server_default='true'))
    op.add_column('user_profiles', sa.Column('is_driver', sa.Boolean(), nullable=False, server_default='false'))

    # 2. Add role_intent column (using the New Enum name)
    role_intent_enum = postgresql.ENUM('RIDER', 'DRIVER', name='roleintentenum')
    role_intent_enum.create(op.get_bind())
    op.add_column('user_profiles', sa.Column('role_intent', sa.Enum('RIDER', 'DRIVER', name='roleintentenum'), nullable=False, server_default='RIDER'))

    # 3. Drop old role column and its enum
    op.drop_column('user_profiles', 'role')

    # Note: We are NOT dropping the old 'roleenum' type here just in case,
    # but in a fresh start it doesn't matter.

    # 4. Remove server defaults
    op.alter_column('user_profiles', 'is_rider', server_default=None)
    op.alter_column('user_profiles', 'is_driver', server_default=None)
    op.alter_column('user_profiles', 'role_intent', server_default=None)


def downgrade() -> None:
    # This is a complex downgrade because of the enum removal,
    # but since tables are truncated, we can just drop and recreate.
    op.add_column('user_profiles', sa.Column('role', sa.VARCHAR(), nullable=False, server_default='RIDER'))
    op.drop_column('user_profiles', 'role_intent')
    op.drop_column('user_profiles', 'is_driver')
    op.drop_column('user_profiles', 'is_rider')
    # Drop the new enum
    sa.Enum(name='roleintentenum').drop(op.get_bind())
