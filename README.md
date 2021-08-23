# synapse-tools

Misc tools for Synapse Matrix server

##  synapse-purge.sh

Script to cleanup Synapse database. 

- Remove rooms without any local user
- Remove remote events older than specific time (effectively truncates history)
- Perform DB maintenance (vacuum/reindex)

See source for requirements.