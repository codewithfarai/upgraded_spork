#!/bin/bash
set -euo pipefail

# ========================================================================
# Map Data Setup Script - Multi-Region (Zim + West Yorkshire/Leeds)
# ========================================================================
# This script:
# 1. Downloads specified OSM PBF extracts
# 2. Merges them into a single unified PBF
# 3. Processes them for OSRM (routing) and Planetiler (vector tiles)
# ========================================================================

DATA_DIR="${DATA_DIR:-/opt/docker/stacks/map_service/data}"
TILES_DIR="${TILES_DIR:-/opt/docker/stacks/map_service/tiles}"
SETUPDONE_FILE="${SETUPDONE_FILE:-$DATA_DIR/.setup_done}"
LOG_FILE="$DATA_DIR/setup.log"

REGIONS=(
  "africa/zimbabwe"
  "europe/united-kingdom/england/west-yorkshire"
)

mkdir -p "$DATA_DIR" "$TILES_DIR"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

# Check if setup is already done
if [ -f "$SETUPDONE_FILE" ]; then
  log "✓ Map data setup already completed. Skipping..."
  exit 0
fi

log "====== Multi-Region Map Data Setup Started ======"

# ==== STEP 1: Download Regions ====
MERGE_INPUTS=()
for REGION in "${REGIONS[@]}"; do
  BASENAME=$(basename "$REGION")
  PBF_FILE="$DATA_DIR/$BASENAME-latest.osm.pbf"
  MERGE_INPUTS+=("/data/$BASENAME-latest.osm.pbf")

  if [ ! -f "$PBF_FILE" ]; then
    log "Downloading $REGION PBF..."
    if wget -q --show-progress -O "$PBF_FILE.tmp" "https://download.geofabrik.de/$REGION-latest.osm.pbf"; then
      mv "$PBF_FILE.tmp" "$PBF_FILE"
      log "✓ $BASENAME downloaded"
    else
      log "ERROR: Failed to download $REGION"
      exit 1
    fi
  else
    log "✓ $BASENAME exists"
  fi
done

# ==== STEP 2: Merge Regions ====
COMBINED_PBF="$DATA_DIR/combined-regions.osm.pbf"
log "Merging regions into unified dataset..."
docker run --rm -v "$DATA_DIR:/data" ubuntu:22.04 sh -c "
  apt-get update -qq &&
  apt-get install -qq -y osmium-tool &&
  osmium merge ${MERGE_INPUTS[*]} -o /data/combined-regions.osm.pbf --overwrite
"

# ==== STEP 3: Process for OSRM (Routing) ====
OSRM_FILE="$DATA_DIR/combined-regions.osrm"
log "Generating OSRM routing graph..."
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend:latest osrm-extract -p /opt/car.lua /data/combined-regions.osm.pbf
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend:latest osrm-partition /data/combined-regions.osrm
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend:latest osrm-customize /data/combined-regions.osrm

# ==== STEP 4: Generate Vector Tiles (Planetiler) ====
MBTILES_FILE="$TILES_DIR/combined.mbtiles"
log "Generating vector tiles (Planetiler @ Xmx5g)..."
docker run -e JAVA_TOOL_OPTIONS="-Xmx5g" --rm \
  -v "$DATA_DIR:/data" \
  -v "$TILES_DIR:/tiles" \
  ghcr.io/onthegomap/planetiler:latest \
  --osm-path=/data/combined-regions.osm.pbf \
  --output=/tiles/combined.mbtiles \
  --force \
  --download

# ==== STEP 5: Create symlinks for Martin tile sources ====
# This allows Martin to serve the combined dataset via the specific
# region names expected by the frontend (e.g. /zimbabwe)
log "Creating symlinks for Martin tile sources..."
for REGION in "${REGIONS[@]}"; do
  BASENAME=$(basename "$REGION")
  # Use relative symlink so it works regardless of the host mount path
  (cd "$TILES_DIR" && ln -sf combined.mbtiles "$BASENAME.mbtiles")
  log "✓ Link created: $BASENAME.mbtiles -> combined.mbtiles"
done

log "✓ All map data generated successfully"
touch "$SETUPDONE_FILE"
log "====== Setup Complete ======"
