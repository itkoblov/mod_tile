#!/bin/bash
render_expired --map=s2o --min-zoom=13 --touch-from=13 --delete-from=19 --max-zoom=20 -s /run/renderd/renderd.sock < /home/renderaccount/data/dirty_tiles.txt
rm /home/ajtown/data/dirty_tiles.txt
