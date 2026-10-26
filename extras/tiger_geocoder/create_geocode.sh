#!/bin/bash
PGPORT=5432
PGHOST=localhost
PGUSER=postgres
# Do not put the database password in this file or in PGPASSWORD: it would
# end up in the process environment and in version control. Use ~/.pgpass
# (chmod 600) or PGPASSFILE instead.
export PGPORT PGHOST PGUSER
THEDB=geocoder
PSQL_CMD=/usr/lib/postgresql/9.4/bin/psql
PGCONTRIB=/usr/share/postgresql/9.4/contrib
#if you are on 9.1+ use the CREATE EXTENSION syntax instead
${PSQL_CMD} -d "${THEDB}" -f "${PGCONTRIB}/fuzzystrmatch.sql"
#${PSQL_CMD} -d "${THEDB}" -c "CREATE EXTENSION fuzzystrmatch" 
${PSQL_CMD} -d "${THEDB}" -c "CREATE SCHEMA tiger"
#unremark this next line and edit if you want the search paths set as part of the install
#${PSQL_CMD} -d "${THEDB}" -c "ALTER DATABASE ${THEDB} SET search_path=public, tiger;"
#${PSQL_CMD} -d "${THEDB}" -f "tables/lookup_tables_2011.sql"
${PSQL_CMD} -d "${THEDB}" -c "CREATE SCHEMA tiger_data"
${PSQL_CMD} -d "${THEDB}" -f "create_geocode.sql"
${PSQL_CMD} -d "${THEDB}" -f "tiger_loader_2016.sql"
