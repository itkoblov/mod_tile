#!/bin/bash
#
# call_pyosmium.sh
#
# Designed to be run from cron, as the user that owns the database (normally "_renderd").
# Note that "render_expired" doesn't use TILEDIR from map name in /etc/renderd.conf
# when deciding if tiles exist already; it assumes they must be below /var/cache .
# It therefore makes sense to use /var/cache/renderd/pyosmium for the files needed here.
#
# To initialise "sequence.state", run:
#
# sudo mkdir /var/cache/renderd/pyosmium
# sudo chown _renderd /var/cache/renderd/pyosmium
# cd /var/cache/renderd/pyosmium
# sudo -u _renderd pyosmium-get-changes -D 2022-06-08T20:21:25Z -f sequence.state -v
#
# with an appropriate date.
#
if [[ ! -f /var/cache/renderd/pyosmium/sequence.state ]]
then
    echo "/var/cache/renderd/pyosmium/sequence.state does not exist"
    exit 1
fi
#
if ! command -v pyosmium-get-changes &> /dev/null
then
    echo "pyosmium-get-changes could not be found"
    exit 1
fi
#
if ! command -v osm2pgsql &> /dev/null
then
    echo "osm2pgsql could not be found"
    exit 1
fi
#
if ! command -v render_expired &> /dev/null
then
    echo "render_expired could not be found"
    exit 1
fi
#
echo
echo "Pyosmium update started: " `date`
#
cd /var/cache/renderd/pyosmium/
rm newchange.osc.gz > pyosmium.$$ 2>&1
pyosmium-get-changes -f sequence.state -o newchange.osc.gz >> pyosmium.$$ 2>&1
#
# The osm2pgsql append line will need to be tailored to match the running system (memory and number of processors), the style in use, and
# the number of zoom levels to write dirty tiles for.
osm2pgsql --append --slim -d gis -C 2500 --number-processes 2 -S /home/ajtown/src/openstreetmap-carto-AJT/openstreetmap-carto.style --multi-geometry --tag-transform-script /home/ajtown/src/SomeoneElse-style/style.lua --expire-tiles=1-20 --expire-output=/var/cache/renderd/pyosmium/dirty_tiles.txt /var/cache/renderd/pyosmium/newchange.osc.gz > osmpgsql.$$ 2>&1
#
# This line is exactly the same as the "expire_tiles.sh"
# that would be used with "update_tiles.sh" (which calls "osm2pgsql-replication update" rather than the more flexible "pyosmium-get-changes")
# The arguments can be tailored to do different things at different zoom levels as desired.
render_expired --map=s2o --min-zoom=13 --touch-from=13 --delete-from=19 --max-zoom=20 -s /run/renderd/renderd.sock < /var/cache/renderd/pyosmium/dirty_tiles.txt > render_expired.$$ 2>&1
#
rm /var/cache/renderd/pyosmium/dirty_tiles.txt >> pyosmium.$$ 2>&1
#
cat pyosmium.$$
rm pyosmium.$$
#
tail -1 osmpgsql.$$
rm osmpgsql.$$
#
tail -9 render_expired.$$
rm render_expired.$$
#
echo "Database Replication Lag:"
pyosmium_replag.sh -h
#
