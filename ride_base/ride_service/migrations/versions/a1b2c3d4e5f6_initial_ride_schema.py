"""initial_ride_schema

Revision ID: a1b2c3d4e5f6
Revises:
Create Date: 2026-04-04 14:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── rides ─────────────────────────────────────────────────────────
    op.create_table(
        "rides",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("ride_guid", sa.String(), nullable=False),
        sa.Column("rider_id", sa.String(), nullable=False),
        sa.Column("driver_id", sa.String(), nullable=True),
        sa.Column("rider_name", sa.String(), nullable=False),
        sa.Column("rider_phone_number", sa.String(), nullable=False),
        sa.Column("driver_name", sa.String(), nullable=True),
        sa.Column("driver_phone_number", sa.String(), nullable=True),
        sa.Column("vehicle_info", sa.String(), nullable=True),
        # Locations
        sa.Column("start_latitude", sa.Float(), nullable=False),
        sa.Column("start_longitude", sa.Float(), nullable=False),
        sa.Column("start_address", sa.String(), nullable=False),
        sa.Column("destination_latitude", sa.Float(), nullable=False),
        sa.Column("destination_longitude", sa.Float(), nullable=False),
        sa.Column("destination_address", sa.String(), nullable=False),
        # Financials
        sa.Column("rider_offer_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("recommended_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("accepted_amount", sa.Numeric(10, 2), nullable=True),
        sa.Column("selected_offer_id", postgresql.UUID(as_uuid=True), nullable=True),
        # Trip metadata
        sa.Column("distance_km", sa.Float(), nullable=False),
        sa.Column("estimated_minutes", sa.Integer(), nullable=False),
        # Driver live state
        sa.Column("driver_eta_minutes", sa.Integer(), nullable=True),
        sa.Column("driver_current_latitude", sa.Float(), nullable=True),
        sa.Column("driver_current_longitude", sa.Float(), nullable=True),
        sa.Column("driver_status_note", sa.String(), nullable=True),
        # Post-trip
        sa.Column("rider_rating", sa.Integer(), nullable=True),
        sa.Column("rider_feedback", sa.Text(), nullable=True),
        # State
        sa.Column("status", sa.String(), nullable=False),
        # Request extras
        sa.Column("comments", sa.Text(), nullable=True),
        sa.Column("is_ordering_for_someone_else", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("requested_for_name", sa.String(), nullable=True),
        # Timestamps
        sa.Column("requested_at_utc", sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at_utc", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at_utc", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_at_utc", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_by", sa.String(), nullable=True),
        sa.Column("cancel_reason_code", sa.String(), nullable=True),
        sa.Column("cancel_reason_text", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_rides_ride_guid", "rides", ["ride_guid"], unique=True)
    op.create_index("ix_rides_rider_id", "rides", ["rider_id"])
    op.create_index("ix_rides_driver_id", "rides", ["driver_id"])

    # ── ride_offers ───────────────────────────────────────────────────
    op.create_table(
        "ride_offers",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("ride_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("rides.id", ondelete="CASCADE"), nullable=False),
        sa.Column("driver_id", sa.String(), nullable=False),
        sa.Column("offer_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("rider_offer_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("recommended_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("is_counter_offer", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("eta_to_pickup_minutes", sa.Integer(), nullable=False),
        sa.Column("distance_km", sa.Float(), nullable=False),
        sa.Column("pickup_address", sa.String(), nullable=False),
        sa.Column("destination_address", sa.String(), nullable=False),
        sa.Column("pickup_latitude", sa.Float(), nullable=False),
        sa.Column("pickup_longitude", sa.Float(), nullable=False),
        sa.Column("destination_latitude", sa.Float(), nullable=False),
        sa.Column("destination_longitude", sa.Float(), nullable=False),
        sa.Column("driver_name", sa.String(), nullable=False),
        sa.Column("driver_phone_number", sa.String(), nullable=False),
        sa.Column("driver_rating", sa.Float(), nullable=True),
        sa.Column("driver_rides_completed", sa.Integer(), nullable=True),
        sa.Column("driver_vehicle", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("offer_time_utc", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_ride_offers_ride_id", "ride_offers", ["ride_id"])
    op.create_index("ix_ride_offers_driver_id", "ride_offers", ["driver_id"])

    # ── sos_incidents ─────────────────────────────────────────────────
    op.create_table(
        "sos_incidents",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("incident_id", sa.String(), nullable=False),
        sa.Column("ride_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("rides.id", ondelete="SET NULL"), nullable=True),
        sa.Column("triggered_by", sa.String(), nullable=False),
        sa.Column("rider_id", sa.String(), nullable=False),
        sa.Column("driver_id", sa.String(), nullable=True),
        sa.Column("driver_name", sa.String(), nullable=True),
        sa.Column("rider_name", sa.String(), nullable=True),
        sa.Column("trip_status", sa.String(), nullable=True),
        sa.Column("reason_code", sa.String(), nullable=False),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("triggered_at_utc", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_sos_incidents_incident_id", "sos_incidents", ["incident_id"], unique=True)
    op.create_index("ix_sos_incidents_ride_id", "sos_incidents", ["ride_id"])
    op.create_index("ix_sos_incidents_rider_id", "sos_incidents", ["rider_id"])

    # ── driver_availability ───────────────────────────────────────────
    op.create_table(
        "driver_availability",
        sa.Column("driver_id", sa.String(), primary_key=True),
        sa.Column("is_online", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("updated_at_utc", sa.DateTime(timezone=True), nullable=False),
    )

    # ── ride_ratings ──────────────────────────────────────────────────
    op.create_table(
        "ride_ratings",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("ride_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("rides.id", ondelete="CASCADE"), nullable=False),
        sa.Column("rider_id", sa.String(), nullable=False),
        sa.Column("driver_id", sa.String(), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("feedback", sa.Text(), nullable=True),
        sa.Column("submitted_at_utc", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_ride_ratings_ride_id", "ride_ratings", ["ride_id"], unique=True)


def downgrade() -> None:
    op.drop_table("ride_ratings")
    op.drop_table("driver_availability")
    op.drop_table("sos_incidents")
    op.drop_table("ride_offers")
    op.drop_table("rides")
