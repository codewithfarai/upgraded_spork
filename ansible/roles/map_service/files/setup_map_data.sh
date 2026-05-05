#!/bin/bash
set -euo pipefail

# ========================================================================
# Map Data Setup Script - OSRM + Martin (Planetiler)
# ========================================================================
# This script downloads Zimbabwe OSM data and processes it for:
# - OSRM (routing engine)
# - Martin (vector tile server via Planetiler)
# ========================================================================

DATA_DIR="${DATA_DIR:-/opt/docker/stacks/map_service/data}"
TILES_DIR="${TILES_DIR:-/opt/docker/stacks/map_service/tiles}"
SETUPDONE_FILE="${SETUPDONE_FILE:-$DATA_DIR/.setup_done}"
LOG_FILE="$DATA_DIR/setup.log"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$TILES_DIR"

# Logging function
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

log "====== Map Data Setup Started ======"
log "Data dir: $DATA_DIR"
log "Tiles dir: $TILES_DIR"

# Check prerequisites
if ! command -v docker &> /dev/null; then
  log "ERROR: Docker is not installed"
  exit 1
fi

log "✓ Docker is available"

# ==== STEP 1: Download Zimbabwe PBF ====
PBF_FILE="$DATA_DIR/zimbabwe-latest.osm.pbf"
if [ ! -f "$PBF_FILE" ]; then
  log "Downloading Zimbabwe OSM PBF extract (this may take 5-10 minutes)..."

  if wget -q --show-progress -O "$PBF_FILE.tmp" "https://download.geofabrik.de/africa/zimbabwe-latest.osm.pbf"; then
    mv "$PBF_FILE.tmp" "$PBF_FILE"
    log "✓ Zimbabwe PBF downloaded successfully ($(du -h "$PBF_FILE" | cut -f1))"
  else
    log "ERROR: Failed to download Zimbabwe PBF"
    rm -f "$PBF_FILE.tmp"
    exit 1
  fi
else
  log "✓ Zimbabwe PBF already exists ($(du -h "$PBF_FILE" | cut -f1))"
fi

# ==== STEP 2: Process for OSRM ====
OSRM_FILE="$DATA_DIR/zimbabwe-latest.osrm"
if [ ! -f "$OSRM_FILE" ]; then
  log "Processing data for OSRM (extract, partition, customize)..."
  log "This may take 5-10 minutes..."

  # Extract
  log "→ OSRM Extract..."
  if ! docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend:latest \
    osrm-extract -p /opt/car.lua /data/zimbabwe-latest.osm.pbf; then
    log "ERROR: OSRM extract failed"
    exit 1
  fi

  # Partition
  log "→ OSRM Partition..."
  if ! docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend:latest \
    osrm-partition /data/zimbabwe-latest.osrm; then
    log "ERROR: OSRM partition failed"
    exit 1
  fi

  # Customize
  log "→ OSRM Customize..."
  if ! docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend:latest \
    osrm-customize /data/zimbabwe-latest.osrm; then
    log "ERROR: OSRM customize failed"
    exit 1
  fi

  log "✓ OSRM processing complete"
else
  log "✓ OSRM data already processed"
fi

# ==== STEP 3: Setup MBTiles for Martin using Planetiler ====
MBTILES_FILE="$TILES_DIR/zimbabwe.mbtiles"
if [ ! -f "$MBTILES_FILE" ]; then
  log "Processing vector tiles using Planetiler (this may take 10-20 minutes)..."
  log "Note: Planetiler will download full OSM data for tile generation..."

  if docker run -e JAVA_TOOL_OPTIONS="-Xmx4g" --rm \
    -v "$DATA_DIR:/data" \
    -v "$TILES_DIR:/tiles" \
    ghcr.io/onthegomap/planetiler:latest \
    --download \
    --osm-path=/data/zimbabwe-latest.osm.pbf \
    --output=/tiles/zimbabwe.mbtiles; then
    log "✓ MBTiles generated successfully ($(du -h "$MBTILES_FILE" | cut -f1))"
  else
    log "ERROR: Planetiler processing failed"
    rm -f "$MBTILES_FILE"
    exit 1
  fi
else
  log "✓ MBTiles already exists ($(du -h "$MBTILES_FILE" | cut -f1))"
fi

# ==== VALIDATION ====
log "Validating setup..."
if [ ! -f "$OSRM_FILE" ]; then
  log "ERROR: OSRM file missing: $OSRM_FILE"
  exit 1
fi

if [ ! -f "$MBTILES_FILE" ]; then
  log "ERROR: MBTiles file missing: $MBTILES_FILE"
  exit 1
fi

log "✓ All validations passed"

# ==== Mark as complete ====
touch "$SETUPDONE_FILE"
log "====== Map Data Setup Completed Successfully ======"
log "Ready to deploy OSRM and Martin services"

echo "Map data setup complete."
