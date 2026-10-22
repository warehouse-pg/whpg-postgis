#!/bin/bash
export PGPORT=5432
export PGHOST=localhost
export PGUSER=postgres
# Do not put the database password in this file or in PGPASSWORD: it would
# end up in the process environment and in version control. Use ~/.pgpass
# (chmod 600) or PGPASSFILE instead.
THEDB=geocoder
PSQL_CMD=/usr/bin/psql
PGCONTRIB=/usr/share/postgresql/contrib
${PSQL_CMD} -d "${THEDB}" -f "upgrade_geocode.sql"

#unremark the loader line to update your loader scripts
#note this wipes out your custom settings in loader_* tables
#${PSQL_CMD} -d "${THEDB}" -f "tiger_loader_2016.sql"
