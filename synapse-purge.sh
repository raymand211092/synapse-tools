#!/bin/bash

# Simple Synapse cleanup script
# Copyright (C) 2021  Romain Recourt<romain@prk.st>
#
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.


# reqs :
# - local DB
# - Postgres DB
# - jq installed (https://stedolan.github.io/jq/)
# - use an account with PG autologin with admin rights
# - local Synapse service running as "matrix-synapse" (for stop/restart)

SYNAPSE_BASE="http://localhost:8008"
DOMAIN="domain.tld"
ADMIN="@admin:domain.tld"
DBNAME="dbname"
DBUSER="dbusr"

# Max history to keep
TIME='180 days ago'
# TODO add TZ to config
UNIX_TIMESTAMP=$(date +%s%3N --date='TZ="UTC+2" '"$TIME")

# TODO should be replaced with a mktemp call...
ROOMLIST=/tmp/roomlist.json
ROOMLIST_PURGE=/tmp/rooms_to_purge.txt

# Get a token
TOKEN=$(psql -t -A -h localhost --dbname=$DBNAME --user=$DBUSER --command="select token from access_tokens where user_id='$ADMIN' order by id desc limit 1;" |grep -v "Pager")
# TODO get a new one if needed

########################
# Unused rooms cleanup #
########################

echo " - Free space before"
df -h

echo ""
echo " - Reading abandonned rooms list"
curl --header "Authorization: Bearer $TOKEN" "${SYNAPSE_BASE}/_synapse/admin/v1/rooms?limit=300" > $ROOMLIST
jq '.rooms[] | select(.joined_local_members == 0) | .room_id' < $ROOMLIST  > $ROOMLIST_PURGE

readarray -t ROOMS_ARRAY < $ROOMLIST_PURGE

for ROOM_NAME in "${ROOMS_ARRAY[@]}"
do
   :
        echo ""
        echo "--- Purging abandonned room $ROOM_NAME "
        curl --header "Authorization: Bearer $TOKEN" -XPOST -H "Content-Type: application/json" -d "{ \"room_id\": ${ROOM_NAME} }" "${SYNAPSE_BASE}/_synapse/admin/v1/purge_room"
done

#################
# Purge history #
#################

echo ""
echo " - Reading rooms list, purging before $UNIX_TIMESTAMP"
curl --header "Authorization: Bearer $TOKEN" "${SYNAPSE_BASE}/_synapse/admin/v1/rooms?limit=300" > $ROOMLIST
jq '.rooms[] | .room_id' < $ROOMLIST  > $ROOMLIST_PURGE

readarray -t ROOMS_ARRAY < $ROOMLIST_PURGE

for ROOM_NAME in "${ROOMS_ARRAY[@]}"
do
   :
        echo ""
        # Yeah, pretty ugly but y'know, json stuff...
        ROOM_NAME_TRIM=$(echo $ROOM_NAME | sed 's/"//g')
        echo "--- Triming history for room $ROOM_NAME_TRIM "

        curl --header "Authorization: Bearer $TOKEN" -XPOST -H "Content-Type: application/json" -d "{ \"delete_local_events\": false, \"purge_up_to_ts\": $UNIX_TIMESTAMP }" "${SYNAPSE_BASE}/_synapse/admin/v1/purge_history/$ROOM_NAME_TRIM"
done

#######################
# Purge media history #
#######################

echo ""
echo " - Purging media before $UNIX_TIMESTAMP"
curl --header "Authorization: Bearer $TOKEN" -XPOST -H "Content-Type: application/json" -d "{ \"delete_local_events\": false, \"purge_up_to_ts\": $UNIX_TIMESTAMP }" "${SYNAPSE_BASE}/_synapse/admin/v1/media/${DOMAIN}/delete?before_ts=${UNIX_TIMESTAMP}"

echo ""
echo " - Purging cached media before $UNIX_TIMESTAMP"
curl --header "Authorization: Bearer $TOKEN" -XPOST -H "Content-Type: application/json" -d "{ \"delete_local_events\": false, \"purge_up_to_ts\": $UNIX_TIMESTAMP }" "${SYNAPSE_BASE}/_synapse/admin/v1/purge_media_cache?before_ts=${UNIX_TIMESTAMP}"


###################
# Cleanup DB
###################

echo ""

echo " - Cleaning database"
echo " --- Stoping server"
service matrix-synapse stop
echo " --- VACUUM"
psql -t -A -h localhost --dbname=$DBNAME --user=$DBUSER --command="VACUUM FULL;"
echo " --- REINDEX"
psql -t -A -h localhost --dbname=$DBNAME --user=$DBUSER --command="REINDEX DATABASE synapsedb;"
echo " --- Restarting server"
service matrix-synapse start

echo " - Free space after"
df -h