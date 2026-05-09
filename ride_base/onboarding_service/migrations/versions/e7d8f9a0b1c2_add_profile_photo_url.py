"""add_profile_photo_url

Revision ID: e7d8f9a0b1c2
Revises: f6d78216210b
Create Date: 2026-05-09 18:22:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e7d8f9a0b1c2'
down_revision: Union[str, Sequence[str], None] = 'f6d78216210b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('user_profiles', sa.Column('profile_photo_url', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('user_profiles', 'profile_photo_url')
