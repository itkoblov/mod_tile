#!/bin/bash
#
# ------------------------------------------------------------------------------
# pyosmium_replag.sh
# derived from /usr/share/doc/libapache2-mod-tile/examples/osmosis-db_replag
# ------------------------------------------------------------------------------
#
# Copyright (c) 2007 - 2020 by mod_tile contributors (see AUTHORS file)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; If not, see http://www.gnu.org/licenses/.
#
statenumber=`cat /var/cache/renderd/pyosmium/sequence.state`
#echo $statenumber
#
state1=`cat /var/cache/renderd/pyosmium/sequence.state | cut -c1`
#echo $state1
#
state2=`cat /var/cache/renderd/pyosmium/sequence.state | cut -c2-4`
#echo $state2
#
state3=`cat /var/cache/renderd/pyosmium/sequence.state | cut -c5-7`
#echo $state3
#
curl -s https://planet.openstreetmap.org/replication/minute/00${state1}/${state2}/${state3}.state.txt > state.$$

STATE=state.$$

rep=$(cat ${STATE} |
  grep 'timestamp' |
  awk '{split($0, a, "="); print a[2]}' |
  tr 'T' ' ' |
  xargs -I{} ${BINPATH}date --utc --date "{}" +%s)
is=$(date --utc +%s)

lag=$(($is - $rep))

if [ "$1" = "-h" ]; then

  if [ $lag -gt 86400 ]; then
    echo $(($lag / 86400)) "day(s) and" $((($lag % 86400) / 3600)) "hour(s)"
  elif [ $lag -gt 3600 ]; then
    echo $(($lag / 3600)) "hour(s)"
  elif [ $lag -gt 60 ]; then
    echo $(($lag / 60)) "minute(s)"
  else
    echo $lag "second(s)"
  fi

else

  echo $lag

fi

rm state.$$
