#!/bin/bash
osm2pgsql-replication update -d gis --post-processing /usr/local/sbin/expire_tiles.sh --max-diff-size 10  -- --multi-geometry --tag-transform-script /home/ajtown/src/SomeoneElse-style/style.lua -C 2500 --number-processes 2 -S /home/ajtown/src/openstreetmap-carto-AJT/openstreetmap-carto.style --expire-tiles=1-20 --expire-output=/home/ajtown/data/dirty_tiles.txt
