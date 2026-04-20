"""Reporting endpoints for drivers and platform admins.

Provides ride history, earnings summaries, driver performance stats,
and platform-wide metrics.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import func, case, and_, extract
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.database import get_db
from app.middleware.auth import get_current_user
from app.models.ride import Ride, RideRating, RideStatus, SosIncident

logger = logging.getLogger(__name__)

router = APIRouter()


def _user_id(user: dict) -> str:
    uid = user.get("authentik_pk") or user.get("sub")
    if not uid:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="unauthorized")
    return str(uid)


# ── Response Models ───────────────────────────────────────────────


class DriverStatsResponse(BaseModel):
    driver_id: str
    total_rides_completed: int
    total_rides_cancelled: int
    total_earnings: float
    average_fare: float
    total_distance_km: float
    average_rating: Optional[float]
    total_ratings: int
    sos_incidents: int


class EarningsPeriodResponse(BaseModel):
    driver_id: str
    period_start: str
    period_end: str
    rides_completed: int
    total_earnings: float
    average_fare: float
    total_distance_km: float


class RideHistoryItem(BaseModel):
    ride_id: str
    status: str
    pickup_address: str
    destination_address: str
    distance_km: float
    accepted_amount: Optional[float]
    rider_offer_amount: float
    rider_name: str
    requested_at: str
    completed_at: Optional[str]
    rating: Optional[int]


class RideHistoryResponse(BaseModel):
    driver_id: str
    total_count: int
    page: int
    page_size: int
    rides: list[RideHistoryItem]


class PlatformStatsResponse(BaseModel):
    total_rides_requested: int
    total_rides_completed: int
    total_rides_cancelled: int
    cancellation_rate: float
    total_revenue: float
    average_fare: float
    total_distance_km: float
    average_rating: float
    total_active_sos: int
    period_start: str
    period_end: str


class DailyBreakdownItem(BaseModel):
    date: str
    rides_completed: int
    earnings: float
    distance_km: float


class DailyBreakdownResponse(BaseModel):
    driver_id: str
    period_start: str
    period_end: str
    days: list[DailyBreakdownItem]


# ── Driver Stats ──────────────────────────────────────────────────


@router.get("/driver/stats", response_model=DriverStatsResponse)
async def get_driver_stats(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get lifetime stats for the authenticated driver."""
    driver_id = _user_id(current_user)

    # Completed rides stats
    completed_q = await db.execute(
        select(
            func.count(Ride.id).label("total_completed"),
            func.coalesce(func.sum(Ride.accepted_amount), 0).label("total_earnings"),
            func.coalesce(func.avg(Ride.accepted_amount), 0).label("avg_fare"),
            func.coalesce(func.sum(Ride.distance_km), 0).label("total_distance"),
        ).where(
            and_(
                Ride.driver_id == driver_id,
                Ride.status == RideStatus.TRIP_COMPLETED.value,
            )
        )
    )
    completed = completed_q.one()

    # Cancelled rides
    cancelled_q = await db.execute(
        select(func.count(Ride.id)).where(
            and_(
                Ride.driver_id == driver_id,
                Ride.status == RideStatus.CANCELLED.value,
            )
        )
    )
    total_cancelled = cancelled_q.scalar() or 0

    # Ratings
    rating_q = await db.execute(
        select(
            func.avg(RideRating.rating).label("avg_rating"),
            func.count(RideRating.id).label("total_ratings"),
        ).where(RideRating.driver_id == driver_id)
    )
    rating_row = rating_q.one()

    # SOS incidents
    sos_q = await db.execute(
        select(func.count(SosIncident.id)).where(SosIncident.driver_id == driver_id)
    )
    sos_count = sos_q.scalar() or 0

    return DriverStatsResponse(
        driver_id=driver_id,
        total_rides_completed=completed.total_completed,
        total_rides_cancelled=total_cancelled,
        total_earnings=float(completed.total_earnings),
        average_fare=float(completed.avg_fare),
        total_distance_km=float(completed.total_distance),
        average_rating=round(float(rating_row.avg_rating), 2) if rating_row.avg_rating else None,
        total_ratings=rating_row.total_ratings,
        sos_incidents=sos_count,
    )


# ── Earnings by Period ────────────────────────────────────────────


@router.get("/driver/earnings", response_model=EarningsPeriodResponse)
async def get_driver_earnings(
    period: str = Query("month", regex="^(today|week|month|year)$"),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get driver earnings for a given time period (today, week, month, year)."""
    driver_id = _user_id(current_user)
    now = datetime.now(timezone.utc)

    if period == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "week":
        start = now - timedelta(days=now.weekday())
        start = start.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "month":
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    elif period == "year":
        start = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)

    result = await db.execute(
        select(
            func.count(Ride.id).label("rides_completed"),
            func.coalesce(func.sum(Ride.accepted_amount), 0).label("total_earnings"),
            func.coalesce(func.avg(Ride.accepted_amount), 0).label("avg_fare"),
            func.coalesce(func.sum(Ride.distance_km), 0).label("total_distance"),
        ).where(
            and_(
                Ride.driver_id == driver_id,
                Ride.status == RideStatus.TRIP_COMPLETED.value,
                Ride.completed_at_utc >= start,
            )
        )
    )
    row = result.one()

    return EarningsPeriodResponse(
        driver_id=driver_id,
        period_start=start.isoformat(),
        period_end=now.isoformat(),
        rides_completed=row.rides_completed,
        total_earnings=float(row.total_earnings),
        average_fare=float(row.avg_fare),
        total_distance_km=float(row.total_distance),
    )


# ── Daily Breakdown ───────────────────────────────────────────────


@router.get("/driver/earnings/daily", response_model=DailyBreakdownResponse)
async def get_daily_breakdown(
    days: int = Query(7, ge=1, le=90),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a day-by-day breakdown of earnings for the last N days."""
    driver_id = _user_id(current_user)
    now = datetime.now(timezone.utc)
    start = (now - timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)

    result = await db.execute(
        select(
            func.date(Ride.completed_at_utc).label("day"),
            func.count(Ride.id).label("rides_completed"),
            func.coalesce(func.sum(Ride.accepted_amount), 0).label("earnings"),
            func.coalesce(func.sum(Ride.distance_km), 0).label("distance"),
        )
        .where(
            and_(
                Ride.driver_id == driver_id,
                Ride.status == RideStatus.TRIP_COMPLETED.value,
                Ride.completed_at_utc >= start,
            )
        )
        .group_by(func.date(Ride.completed_at_utc))
        .order_by(func.date(Ride.completed_at_utc))
    )
    rows = result.all()

    return DailyBreakdownResponse(
        driver_id=driver_id,
        period_start=start.isoformat(),
        period_end=now.isoformat(),
        days=[
            DailyBreakdownItem(
                date=str(r.day),
                rides_completed=r.rides_completed,
                earnings=float(r.earnings),
                distance_km=float(r.distance),
            )
            for r in rows
        ],
    )


# ── Ride History ──────────────────────────────────────────────────


@router.get("/driver/rides", response_model=RideHistoryResponse)
async def get_ride_history(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status_filter: Optional[str] = Query(None, alias="status"),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get paginated ride history for the authenticated driver."""
    driver_id = _user_id(current_user)

    # Count total
    count_q = select(func.count(Ride.id)).where(Ride.driver_id == driver_id)
    if status_filter:
        count_q = count_q.where(Ride.status == status_filter)
    total_count = (await db.execute(count_q)).scalar() or 0

    # Fetch page
    query = (
        select(Ride)
        .where(Ride.driver_id == driver_id)
        .order_by(Ride.requested_at_utc.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    if status_filter:
        query = query.where(Ride.status == status_filter)

    result = await db.execute(query)
    rides = result.scalars().all()

    # Fetch ratings for these rides in one query
    ride_ids = [r.id for r in rides]
    ratings_q = await db.execute(
        select(RideRating.ride_id, RideRating.rating).where(RideRating.ride_id.in_(ride_ids))
    )
    ratings_map = {str(r.ride_id): r.rating for r in ratings_q.all()}

    return RideHistoryResponse(
        driver_id=driver_id,
        total_count=total_count,
        page=page,
        page_size=page_size,
        rides=[
            RideHistoryItem(
                ride_id=r.ride_guid,
                status=r.status,
                pickup_address=r.start_address,
                destination_address=r.destination_address,
                distance_km=r.distance_km,
                accepted_amount=float(r.accepted_amount) if r.accepted_amount else None,
                rider_offer_amount=float(r.rider_offer_amount),
                rider_name=r.rider_name,
                requested_at=r.requested_at_utc.isoformat(),
                completed_at=r.completed_at_utc.isoformat() if r.completed_at_utc else None,
                rating=ratings_map.get(str(r.id)),
            )
            for r in rides
        ],
    )


# ── Platform-Wide Stats (Admin) ──────────────────────────────────


@router.get("/platform/stats", response_model=PlatformStatsResponse)
async def get_platform_stats(
    period: str = Query("month", regex="^(today|week|month|year|all)$"),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Platform-wide ride statistics. Intended for admin dashboards."""
    now = datetime.now(timezone.utc)

    if period == "all":
        start = datetime(2020, 1, 1, tzinfo=timezone.utc)
    elif period == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "week":
        start = now - timedelta(days=now.weekday())
        start = start.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "month":
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    elif period == "year":
        start = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)

    # Total requested
    total_requested = (await db.execute(
        select(func.count(Ride.id)).where(Ride.requested_at_utc >= start)
    )).scalar() or 0

    # Completed
    completed_q = await db.execute(
        select(
            func.count(Ride.id).label("count"),
            func.coalesce(func.sum(Ride.accepted_amount), 0).label("revenue"),
            func.coalesce(func.avg(Ride.accepted_amount), 0).label("avg_fare"),
            func.coalesce(func.sum(Ride.distance_km), 0).label("distance"),
        ).where(
            and_(
                Ride.status == RideStatus.TRIP_COMPLETED.value,
                Ride.completed_at_utc >= start,
            )
        )
    )
    completed = completed_q.one()

    # Cancelled
    total_cancelled = (await db.execute(
        select(func.count(Ride.id)).where(
            and_(
                Ride.status == RideStatus.CANCELLED.value,
                Ride.requested_at_utc >= start,
            )
        )
    )).scalar() or 0

    # Average rating
    avg_rating_q = await db.execute(
        select(func.avg(RideRating.rating)).where(RideRating.submitted_at_utc >= start)
    )
    avg_rating = avg_rating_q.scalar() or 0

    # Active SOS
    active_sos = (await db.execute(
        select(func.count(SosIncident.id)).where(
            and_(
                SosIncident.status == "Received",
                SosIncident.triggered_at_utc >= start,
            )
        )
    )).scalar() or 0

    cancellation_rate = (total_cancelled / total_requested * 100) if total_requested > 0 else 0

    return PlatformStatsResponse(
        total_rides_requested=total_requested,
        total_rides_completed=completed.count,
        total_rides_cancelled=total_cancelled,
        cancellation_rate=round(cancellation_rate, 1),
        total_revenue=float(completed.revenue),
        average_fare=float(completed.avg_fare),
        total_distance_km=float(completed.distance),
        average_rating=round(float(avg_rating), 2),
        total_active_sos=active_sos,
        period_start=start.isoformat(),
        period_end=now.isoformat(),
    )
