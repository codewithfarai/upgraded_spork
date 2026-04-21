#!/bin/bash
set -e

DATA_DIR="/opt/docker/stacks/map_service/data"
TILES_DIR="/opt/docker/stacks/map_service/tiles"

# 1. Download Zimbabwe PBF if it doesn't exist
if [ ! -f "$DATA_DIR/zimbabwe-latest.osm.pbf" ]; then
    echo "Downloading Zimbabwe PBF extract..."
    wget -q --show-progress -O "$DATA_DIR/zimbabwe-latest.osm.pbf" "https://download.geofabrik.de/africa/zimbabwe-latest.osm.pbf"
else
    echo "Zimbabwe PBF already exists."
fi

# 2. Process for OSRM (if not already done)
if [ ! -f "$DATA_DIR/zimbabwe-latest.osrm" ]; then
    echo "Processing data for OSRM..."

    # Extract
    docker run --rm -v $DATA_DIR:/data osrm/osrm-backend osrm-extract -p /opt/car.lua /data/zimbabwe-latest.osm.pbf

    # Partition
    docker run --rm -v $DATA_DIR:/data osrm/osrm-backend osrm-partition /data/zimbabwe-latest.osrm

    # Customize
    docker run --rm -v $DATA_DIR:/data osrm/osrm-backend osrm-customize /data/zimbabwe-latest.osrm
else
    echo "OSRM processing already done."
fi

# 3. Setup PMTiles/MBTiles for Martin using Planetiler
if [ ! -f "$TILES_DIR/zimbabwe.mbtiles" ]; then
    echo "Processing vector tiles using Planetiler (This may take 1-2 minutes)..."

    # Run Planetiler to convert OSM PBF into standard MapTiler schema MBTiles
    docker run -e JAVA_TOOL_OPTIONS="-Xmx4g" --rm \
      -v $DATA_DIR:/data \
      -v $TILES_DIR:/tiles \
      ghcr.io/onthegomap/planetiler:latest \
      --download \
      --osm-path=/data/zimbabwe-latest.osm.pbf \
      --output=/tiles/zimbabwe.mbtiles
else
    echo "MBTiles already generated."
fi

# We use both signals to determine if it's totally done
if [ -f "$DATA_DIR/zimbabwe-latest.osrm" ] && [ -f "$TILES_DIR/zimbabwe.mbtiles" ]; then
    touch "$DATA_DIR/.setup_done"
fi
echo "Map data setup complete."
