"""add driver and rider stats to user profiles

Revision ID: 4d405d674231
Revises: 43f569adb4f4
Create Date: 2026-05-10 19:07:27.903962

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4d405d674231'
down_revision: Union[str, Sequence[str], None] = '43f569adb4f4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add columns with server_default to handle existing rows
    op.add_column('user_profiles', sa.Column('driver_rating_avg', sa.Float(), nullable=False, server_default='5.0'))
    op.add_column('user_profiles', sa.Column('driver_rating_count', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('user_profiles', sa.Column('driver_rides_count', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('user_profiles', sa.Column('rider_rating_avg', sa.Float(), nullable=False, server_default='5.0'))
    op.add_column('user_profiles', sa.Column('rider_rating_count', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('user_profiles', sa.Column('rider_rides_count', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('user_profiles', 'rider_rides_count')
    op.drop_column('user_profiles', 'rider_rating_count')
    op.drop_column('user_profiles', 'rider_rating_avg')
    op.drop_column('user_profiles', 'driver_rides_count')
    op.drop_column('user_profiles', 'driver_rating_count')
    op.drop_column('user_profiles', 'driver_rating_avg')
