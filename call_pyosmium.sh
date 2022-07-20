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
local_filesystem_user=renderaccount
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
if [[ -f /var/cache/renderd/pyosmium/call_pyosmium.running ]]
then
    echo "call_pyosmium alreadying running; /var/cache/renderd/pyosmium/call_pyosmium.running exists"
    exit 1
else
    touch /var/cache/renderd/pyosmium/call_pyosmium.running
fi
#
echo
echo "Pyosmium update started: " `date`
#
cd /var/cache/renderd/pyosmium/
rm newchange.osc.gz > pyosmium.$$ 2>&1
cp sequence.state sequence.state.old
#------------------------------------------------------------------------------
# "-s 20" here means "get 20MB at once".  
# The value can be adjusted up or down as needed.
#------------------------------------------------------------------------------
#
pyosmium-get-changes -f sequence.state -o newchange.osc.gz -s 20 >> pyosmium.$$ 2>&1
#
#------------------------------------------------------------------------------
# Trim the downloaded changes to only the ones that apply to our region.
#
# When using trim_osc.py we can define either a bounding box (such as this
# example for England and Wales) or a polygon.
# See https://github.com/zverik/regional .
# This area will usually correspond to the data originally loaded.
#------------------------------------------------------------------------------
TRIM_BIN=/home/ajtown/src/regional/trim_osc.py
TRIM_REGION_OPTIONS="-b -14.17 48.85 2.12 61.27"
#TRIM_REGION_OPTIONS="-p region.poly"

if [[ -f $TRIM_BIN ]]
then
    echo "Filtering newchange.osc.gz"
    if ! $TRIM_BIN -d gis $TRIM_REGION_OPTIONS  -z newchange.osc.gz newchange.osc.gz > trim.$$ 2>&1
    then
        echo "Trim_osc error but continue anyway"
    fi
else
    echo "${TRIM_BIN} does not exist"
    exit 1
fi
#
#------------------------------------------------------------------------------
# Welsh, English and Scottish names need to be converted to "cy or en", "en" and "gd or en" respectively.
# First, convert a Welsh name portion into Welsh
#------------------------------------------------------------------------------
if osmium extract --polygon /home/${local_filesystem_user}/src/SomeoneElse-style/welsh_areas.geojson newchange.osc.gz -O -o welshlangpart_newchange_before.osc.gz
then
    echo Welsh Extract OK
else
    echo Welsh Extract Error
    exit 1
fi

if /home/${local_filesystem_user}/src/osm-tags-transform/build/src/osm-tags-transform -c /home/${local_filesystem_user}/src/SomeoneElse-style/transform_cy.lua welshlangpart_newchange_before.osc.gz -O -o welshlangpart_newchange_after.osc.gz
then
    echo Welsh Transform OK
else
    echo Welsh Transform Error
    exit 1
fi

#------------------------------------------------------------------------------
# Likewise, Scots Gaelic
#------------------------------------------------------------------------------
if osmium extract --polygon /home/${local_filesystem_user}/src/SomeoneElse-style/scotsgd_areas.geojson newchange.osc.gz -O -o scotsgdlangpart_newchange_before.osc.gz
then
    echo ScotsGD Extract OK
else
    echo ScotsGD Extract Error
    exit 1
fi

if /home/${local_filesystem_user}/src/osm-tags-transform/build/src/osm-tags-transform -c /home/${local_filesystem_user}/src/SomeoneElse-style/transform_gd.lua scotsgdlangpart_newchange_before.osc.gz -O -o scotsgdlangpart_newchange_after.osc.gz
then
    echo ScotsGD Transform OK
else
    echo ScotsGD Transform Error
    exit 1
fi

#------------------------------------------------------------------------------
# Unlike when using osmosis, which merges in a predictable way,
# with osmium we have to explicitly extract the "English" part before conversion.
# The "English" geojson is a large multipolygon with the "Welsh" and "ScotsGD" areas as holes
# (using the exact same co-ordinates).
#------------------------------------------------------------------------------
if osmium extract --polygon /home/${local_filesystem_user}/src/SomeoneElse-style/english_areas.geojson newchange.osc.gz -O -o englishlangpart_newchange_before.osc.gz
then
    echo English Extract OK
else
    echo English Extract Error
    exit 1
fi

if /home/${local_filesystem_user}/src/osm-tags-transform/build/src/osm-tags-transform -c /home/${local_filesystem_user}/src/SomeoneElse-style/transform_en.lua englishlangpart_newchange_before.osc.gz -O -o englishlangpart_newchange_after.osc.gz
then
    echo English Transform OK
else
    echo English Transform Error
    exit 1
fi

#------------------------------------------------------------------------------
# Unlike when using osmosis, which merges in a predictable way,
# with osmium we have to explicitly extract the "Ireland" part before conversion.
# The "Ireland" geojson does not need transforming.
#------------------------------------------------------------------------------
if osmium extract --polygon /home/${local_filesystem_user}/src/SomeoneElse-style/ireland.geojson newchange.osc.gz -O -o irelandpart_newchange.osc.gz
then
    echo Ireland Extract OK
else
    echo Ireland Extract Error
    exit 1
fi

#------------------------------------------------------------------------------
# With "osmium merge" there is no way to merge so that cy and gd files take precedence
# over the en one, but following the extracts above all should be mutually exclusive.
#------------------------------------------------------------------------------
if osmium merge irelandpart_newchange.osc.gz englishlangpart_newchange_after.osc.gz welshlangpart_newchange_after.osc.gz scotsgdlangpart_newchange_after.osc.gz -O -o newchange_merged.osc.gz
then
    echo Merge OK
else
    echo Merge Error
    exit 1
fi

#------------------------------------------------------------------------------
# The osm2pgsql append line will need to be tailored to match the running system (memory and number of processors), the style in use, and
# the number of zoom levels to write dirty tiles for.
#------------------------------------------------------------------------------
echo "Importing newchange.osc.gz"
if ! osm2pgsql --append --slim -d gis -C 2500 --number-processes 2 -S /home/ajtown/src/openstreetmap-carto-AJT/openstreetmap-carto.style --multi-geometry --tag-transform-script /home/ajtown/src/SomeoneElse-style/style.lua --expire-tiles=1-20 --expire-output=/var/cache/renderd/pyosmium/dirty_tiles.txt /var/cache/renderd/pyosmium/newchange_merged.osc.gz > osm2pgsql.$$ 2>&1
then
    # ------------------------------------------------------------------------------
    # The osm2pgsql import failed; show the error, revert to the previous import
    # sequence and remove the "running" flag to try again.
    # Don't delete the command output files to allow later investigation.
    # ------------------------------------------------------------------------------
    echo "osm2pgsql append error"
    cat osm2pgsql.$$
    cp sequence.state.old sequence.state
    rm /var/cache/renderd/pyosmium/call_pyosmium.running
    exit 1
else
    tail -1 osm2pgsql.$$
fi
#
#------------------------------------------------------------------------------
# This line is exactly the same as the "expire_tiles.sh"
# that would be used with "update_tiles.sh" (which calls "osm2pgsql-replication update" rather than the more flexible "pyosmium-get-changes")
# The arguments can be tailored to do different things at different zoom levels as desired.
#------------------------------------------------------------------------------
echo "Expiring tiles"
render_expired --map=s2o --min-zoom=13 --touch-from=13 --delete-from=19 --max-zoom=20 -s /run/renderd/renderd.sock < /var/cache/renderd/pyosmium/dirty_tiles.txt > render_expired.$$ 2>&1
tail -9 render_expired.$$
#
rm /var/cache/renderd/pyosmium/dirty_tiles.txt >> pyosmium.$$ 2>&1
#
#------------------------------------------------------------------------------
# Tidy up files containing output from each command and the file that shows
# that the script is running
#------------------------------------------------------------------------------
rm trim.$$
rm osm2pgsql.$$
rm render_expired.$$
rm pyosmium.$$
rm /var/cache/renderd/pyosmium/call_pyosmium.running
#
echo "Database Replication Lag:" `pyosmium_replag.sh -h`
#
