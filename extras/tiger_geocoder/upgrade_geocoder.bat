set PGPORT=5432
set PGHOST=localhost
set PGUSER=postgres
REM Do not put the database password in this file or in PGPASSWORD.
REM Use %APPDATA%\postgresql\pgpass.conf or PGPASSFILE instead.
set THEDB=geocoder
set PGBIN=C:\Program Files\PostgreSQL\10\bin
set PGCONTRIB=C:\Program Files\PostgreSQL\10\share\contrib

"%PGBIN%\psql"  -d "%THEDB%" -f "upgrade_geocode.sql"

REM "%PGBIN%\psql" -d "%THEDB%" -c "ALTER EXTENSION postgis_tiger_geocoder UPDATE;"

REM unremark the loader line to update your loader scripts
REM note this wipes out your custom settings in loader_* tables
REM "%PGBIN%\psql"  -d "%THEDB%" -f "tiger_loader_2019.sql"
cd regress
REM "%PGBIN%\psql"  -d "%THEDB%" -t -f regress.sql
pause
