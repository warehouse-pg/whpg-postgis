#!/usr/bin/env bash
#
# whpg/validate_whpg19.sh - validate whpg-postgis against a live WHPG19 cluster.
#
# Usage:  whpg/validate_whpg19.sh [phase ...]
#
# Phases (default: preflight smoke base upgrade):
#   preflight   environment, installed artifacts, cluster reachability
#   rebuild     ./configure --prefix=$GPHOME --without-topology --without-protobuf, make, make install
#               (product scope; not run by default)
#   install     finish the aborted `make install` (raster loader utils extensions);
#               not run by default, pass it explicitly
#   smoke       CREATE EXTENSION + distributed queries for every extension
#   base        make installcheck-base  (core/loader/dumper/tiger/sfcgal/topo/raster)
#   upgrade     make installcheck-upgrade (3 upgrade paths; slow)
#   all         preflight smoke base upgrade
#
# Environment (defaults shown):
#   WHPG19_HOME=/Users/tkepe/git/reviews/my_pr_reviews/warehouse-pg-next/build  (becomes GPHOME;
#               an inherited GPHOME pointing elsewhere, e.g. the WHPG7 tree, is ignored with a warning)
#   PGPORT=5432  PGUSER=tkepe  PGHOST=localhost  PGDATABASE=postgres
#   RUNTESTFLAGS=-v
#
# Everything is tee'd into whpg/validation-logs/. Hand that directory back for analysis.

set -u

SRCDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="${SRCDIR}/whpg/validation-logs"
# The interactive shell usually has GPHOME exported for the WHPG7 tree; this
# script validates WHPG19, so it pins GPHOME to WHPG19_HOME and only warns.
WHPG19_HOME="${WHPG19_HOME:-/Users/tkepe/git/reviews/my_pr_reviews/warehouse-pg-next/build}"
if [ -n "${GPHOME:-}" ] && [ "${GPHOME}" != "${WHPG19_HOME}" ]; then
  echo "WARNING: ignoring GPHOME=${GPHOME} from the environment; using WHPG19_HOME=${WHPG19_HOME}" >&2
fi
export GPHOME="${WHPG19_HOME}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-tkepe}"
export PGHOST="${PGHOST:-localhost}"
export PGDATABASE="${PGDATABASE:-postgres}"
export PATH="${GPHOME}/bin:${PATH}"
export RUNTESTFLAGS="${RUNTESTFLAGS:--v}"
export PGOPTIONS="${PGOPTIONS:-}"

mkdir -p "${LOGDIR}"
SUMMARY="${LOGDIR}/SUMMARY.txt"
PHASES=("$@")
[ ${#PHASES[@]} -eq 0 ] && PHASES=(preflight smoke base upgrade)
[ "${PHASES[*]}" = "all" ] && PHASES=(preflight smoke base upgrade)

ts() { date '+%Y-%m-%d %H:%M:%S'; }
note() { echo "[$(ts)] $*" | tee -a "${SUMMARY}"; }
result() { # result <phase> <rc> [detail]
  local st="PASS"; [ "$2" -ne 0 ] && st="FAIL"
  note "RESULT ${1}: ${st} (rc=$2) ${3:-}"
}

# Preserve regress scratch per phase so *_diff files survive for analysis.
save_regress_tmp() { # save_regress_tmp <phase>
  local src="${PGIS_REG_TMPDIR:-/tmp/pgis_reg}"
  if [ -d "${src}" ]; then
    rm -rf "${LOGDIR}/pgis_reg_$1"
    cp -R "${src}" "${LOGDIR}/pgis_reg_$1" 2>/dev/null
    # keep only the useful bits (diffs, logs, obtained outputs of failures)
    find "${LOGDIR}/pgis_reg_$1" -type f ! -name '*_diff' ! -name 'regress_log' \
         ! -name '*.err' ! -name 'objects_*' ! -name 'loader.out' -delete 2>/dev/null
    find "${LOGDIR}/pgis_reg_$1" -type d -empty -delete 2>/dev/null
  fi
}

extract_failures() { # extract_failures <logfile> <outfile>
  { echo "== lines containing ' failed' / 'FAIL' / 'Error' =="
    grep -nE ' failed|^FAIL|\*\*\* \[|Error [0-9]|ERROR:|differ|Object count' "$1" | head -400
    echo; echo "== run_test.pl summary =="
    grep -nE 'Run tests:|Failed:|Skipped:|Passed:' "$1" | tail -20
  } > "$2" 2>&1
}

###############################################################################
phase_preflight() {
  local log="${LOGDIR}/preflight.log" rc=0
  {
    echo "### $(ts) preflight"
    echo "SRCDIR=${SRCDIR}"; echo "GPHOME=${GPHOME}"
    echo "PGHOST=${PGHOST} PGPORT=${PGPORT} PGUSER=${PGUSER}"
    echo; echo "## git"
    (cd "${SRCDIR}" && git rev-parse --abbrev-ref HEAD && git log --oneline -1 && git status --short | grep -v '^??' )
    echo; echo "## toolchain"
    for t in pg_config psql perl make cmake shp2pgsql pgsql2shp raster2pgsql pgtopo_import; do
      printf '%-14s %s\n' "$t" "$(command -v $t 2>/dev/null || echo MISSING)"
    done
    echo; echo "## pg_config"
    pg_config --version; pg_config --pkglibdir; pg_config --sharedir
    [ "$(pg_config --bindir)" = "${GPHOME}/bin" ] || { echo "!! pg_config is not from GPHOME"; rc=1; }
    echo; echo "## gpdiff.pl (required by regress/run_test.pl on WHPG)"
    local gpdiff="${GPHOME}/lib/postgresql/pgxs/src/test/regress/gpdiff.pl"
    if [ -x "${gpdiff}" ]; then echo "ok ${gpdiff}"; else echo "!! MISSING ${gpdiff}"; rc=1; fi
    for f in atmsort.pm explain.pm GPTest.pm; do
      [ -e "${GPHOME}/lib/postgresql/pgxs/src/test/regress/$f" ] && echo "ok $f" || echo "?? $f not found next to gpdiff.pl"
    done
    echo; echo "## installed libraries ($(pg_config --pkglibdir))"
    for lib in postgis-3 postgis_raster-3 address_standardizer-3; do  # product scope; topology/sfcgal intentionally excluded
      local p; p=$(ls "$(pg_config --pkglibdir)"/${lib}.* 2>/dev/null | head -1)
      if [ -n "$p" ]; then echo "ok   $p ($(stat -f '%Sm' "$p"))"; else echo "!! MISSING ${lib}"; rc=1; fi
    done
    echo; echo "## installed extension control files"
    for e in postgis postgis_raster postgis_tiger_geocoder address_standardizer address_standardizer_data_us; do
      local c="$(pg_config --sharedir)/extension/${e}.control"
      if [ -e "$c" ]; then
        echo "ok   ${e} default_version=$(sed -n "s/^default_version *= *'\(.*\)'/\1/p" "$c")  scripts=$(ls "$(pg_config --sharedir)"/extension/${e}--*.sql 2>/dev/null | wc -l | tr -d ' ')"
      else echo "!! MISSING $c"; rc=1; fi
    done
    echo; echo "## contrib SQL (used by non-extension installcheck paths)"
    ls -la "$(pg_config --sharedir)/contrib/postgis-3.6/" 2>&1 | head -40
    echo; echo "## install.log status"
    if grep -q 'man-install\] Error' "${SRCDIR}/install.log" 2>/dev/null; then
      echo "note: the original top-level make install aborted at doc/man-install; the install phase of this script completes it (file presence verified above)"
    fi
    echo; echo "## cluster"
    psql -XtA -c "select version()" || { echo "!! cannot connect"; rc=1; }
    psql -XtA -c "show server_version_num"
    local srvmaj climaj
    srvmaj=$(psql -XtA -c "show server_version_num" 2>/dev/null | cut -c1-2)
    climaj=$(pg_config --version | sed -E 's/^PostgreSQL ([0-9]+).*/\1/')
    [ "${srvmaj}" = "${climaj}" ] || echo "!! server major ${srvmaj} != pg_config/GPHOME major ${climaj}: wrong GPHOME?"
    psql -XtA -c "show optimizer" 2>/dev/null
    psql -XtA -c "show gp_create_table_random_default_distribution" 2>/dev/null
    psql -X -c "select dbid, content, role, preferred_role, mode, status, port, datadir from gp_segment_configuration order by content, role"
    psql -XtA -c "select name, default_version, installed_version from pg_available_extensions where name like 'postgis%' or name like 'address_standardizer%' or name in ('fuzzystrmatch','plpython3u') order by 1"
    psql -XtA -c "select datname from pg_database where datname like 'postgis_reg%' or datname like 'pgis_%'" | sed 's/^/existing test db: /'
    echo; echo "## PATH"; echo "$PATH"
  } 2>&1 | tee "${log}"
  grep -q '^!!' "${log}" && rc=1
  result preflight "${rc}" "$(grep -c '^!!' "${log}") problem line(s), see preflight.log"
  return "${rc}"
}

###############################################################################
phase_install() {
  local log="${LOGDIR}/install.log" rc=0
  {
    echo "### $(ts) finishing make install for the sub-dirs skipped after the man-install abort"
    cd "${SRCDIR}" || exit 1
    # ./configure ran without --prefix, so the non-PGXS pieces (loader CLIs,
    # postgis_restore, man pages) default to /usr/local/{bin,share/man} and
    # fail with EACCES. Redirect them into GPHOME on the make command line.
    local ovr=(bindir="${GPHOME}/bin" mandir="${GPHOME}/share/man")
    for s in raster loader utils extensions doc; do
      echo "---- Making install in ${s}"
      make -C "${s}" install "${ovr[@]}" || { echo "!! make -C ${s} install failed"; rc=1; }
    done
  } 2>&1 | tee "${log}"
  grep -q '^!!' "${log}" && rc=1
  result install "${rc}"
  return "${rc}"
}

###############################################################################
phase_rebuild() {
  # Re-configure to match the product build (whpg/CMakeLists.txt): prefix into
  # GPHOME, raster on, topology, protobuf and sfcgal off (none are shipped).
  local log="${LOGDIR}/rebuild.log" rc=0
  {
    echo "### $(ts) reconfigure + rebuild + install (product scope)"
    cd "${SRCDIR}" || exit 1
    make clean >/dev/null 2>&1 || true
    ./configure --prefix="${GPHOME}" --with-pgconfig="${GPHOME}/bin/pg_config" \
                --with-raster --without-topology --without-protobuf --without-sfcgal \
      && make -j"${JOBS:-8}" \
      && make install
    echo "rebuild rc=$?"
    # remove topology artifacts left over from the earlier with-topology install
    rm -f "$(pg_config --pkglibdir)"/postgis_topology-3.* \
          "$(pg_config --sharedir)"/extension/postgis_topology* \
          "$(pg_config --sharedir)"/contrib/postgis-3.6/topology*.sql \
          "$(pg_config --sharedir)"/contrib/postgis-3.6/uninstall_topology.sql \
          "$(pg_config --pkglibdir)"/postgis_sfcgal-3.* \
          "$(pg_config --sharedir)"/extension/postgis_sfcgal* \
          "$(pg_config --sharedir)"/contrib/postgis-3.6/sfcgal*.sql \
          "$(pg_config --sharedir)"/contrib/postgis-3.6/uninstall_sfcgal.sql
    grep -n "TOPOLOGY\|PROTOBUF\|SFCGAL\|RASTER" postgis_config.h
  } 2>&1 | tee "${log}"
  rc=$(grep -E '^rebuild rc=' "${log}" | tail -1 | sed 's/.*rc=//'); rc="${rc:-1}"
  result rebuild "${rc}" "see rebuild.log"
  return "${rc}"
}

###############################################################################
phase_smoke() {
  local log="${LOGDIR}/smoke.log" rc=0 db="pgis_smoke_whpg19" rc_core=1 rc_topo=1 rc_sfc=1 rc_tiger=1
  # Product scope (what whpg/CMakeLists.txt ships): postgis, postgis_raster,
  # postgis_tiger_geocoder, address_standardizer. topology and sfcgal are built
  # in this dev tree but are NOT part of the product build; they run as
  # separate, non-fatal sections so a failure there does not hide core results.
  cat > "${LOGDIR}/smoke-core.sql" <<'EOSQL'
\set ON_ERROR_STOP on
\set ECHO queries
\timing off
\set ON_ERROR_STOP on
\set ECHO queries
\timing off
select version();
show optimizer;
select count(*) as primary_segments from gp_segment_configuration where role='p' and content>=0;

-- ---------------------------------------------------------------- extensions
CREATE EXTENSION postgis;
SELECT postgis_full_version();
SELECT postgis_lib_version(), postgis_scripts_installed(), postgis_scripts_released();
SELECT postgis_extensions_upgrade();
CREATE EXTENSION postgis_raster;
SELECT postgis_raster_lib_version(), postgis_raster_scripts_installed();
CREATE EXTENSION address_standardizer;
CREATE EXTENSION address_standardizer_data_us;
SELECT extname, extversion, extrelocatable, extnamespace::regnamespace FROM pg_extension WHERE extname NOT IN ('plpgsql') ORDER BY 1;

-- spatial_ref_sys must be REPLICATED on GPDB (branch commit 9717b9c07)
SELECT c.relname, p.policytype, p.numsegments FROM gp_distribution_policy p JOIN pg_class c ON c.oid=p.localoid WHERE c.relname='spatial_ref_sys';
SELECT count(*) FROM spatial_ref_sys;
SELECT count(*) FROM spatial_ref_sys WHERE srid IN (4326, 3857);

-- ---------------------------------------------------------------- geometry, hash distributed
CREATE TABLE smoke_pts (id int, geom geometry(Point,4326)) DISTRIBUTED BY (id);
INSERT INTO smoke_pts SELECT i, ST_SetSRID(ST_MakePoint(-180 + (i % 360), -80 + (i % 160)), 4326) FROM generate_series(1, 20000) i;
CREATE INDEX smoke_pts_gix ON smoke_pts USING gist (geom);
CREATE INDEX smoke_pts_spgix ON smoke_pts USING spgist (geom);
CREATE INDEX smoke_pts_brin ON smoke_pts USING brin (geom);
ANALYZE smoke_pts;
SELECT count(*) AS rows, count(DISTINCT gp_segment_id) AS segments_used FROM smoke_pts;
SELECT count(*) FROM smoke_pts WHERE ST_DWithin(geom, ST_SetSRID(ST_MakePoint(0,0),4326), 10);
SELECT count(*) FROM smoke_pts WHERE geom && ST_MakeEnvelope(-10,-10,10,10,4326);
SELECT ST_AsText(ST_Extent(geom)) FROM smoke_pts;
SELECT ST_AsText(ST_Centroid(ST_Collect(geom))) FROM smoke_pts;
-- binary send/recv round trip and text/ewkb/geojson output on segments
SELECT bool_and(geom = ST_GeomFromEWKB(ST_AsEWKB(geom))) FROM smoke_pts;
SELECT bool_and(geom = ST_GeomFromGeoJSON(ST_AsGeoJSON(geom))) FROM smoke_pts;
SELECT bool_and(ST_SRID(geom)=4326) FROM smoke_pts;
-- estimated extent (uses stats shipped from segments)
SELECT ST_EstimatedExtent('public','smoke_pts','geom') IS NOT NULL;

-- ---------------------------------------------------------------- redistribution motion carries geometry
CREATE TABLE smoke_polys (id int, geom geometry(Polygon,4326)) DISTRIBUTED RANDOMLY;
INSERT INTO smoke_polys SELECT i, ST_Buffer(ST_SetSRID(ST_MakePoint((i*7)%170 - 85, (i*3)%80 - 40),4326), 2) FROM generate_series(1,200) i;
ANALYZE smoke_polys;
SET optimizer = on;
EXPLAIN (COSTS OFF) SELECT count(*) FROM smoke_pts p JOIN smoke_polys q ON ST_Intersects(p.geom, q.geom);
SELECT count(*) AS orca_join FROM smoke_pts p JOIN smoke_polys q ON ST_Intersects(p.geom, q.geom);
SELECT ST_NPoints(ST_Union(geom)) > 0 AS orca_union FROM smoke_polys;
SELECT ST_AsText(ST_Collect(ST_Centroid(geom))) IS NOT NULL AS orca_collect FROM smoke_polys;
SET optimizer = off;
EXPLAIN (COSTS OFF) SELECT count(*) FROM smoke_pts p JOIN smoke_polys q ON ST_Intersects(p.geom, q.geom);
SELECT count(*) AS planner_join FROM smoke_pts p JOIN smoke_polys q ON ST_Intersects(p.geom, q.geom);
SELECT ST_NPoints(ST_Union(geom)) > 0 AS planner_union FROM smoke_polys;
RESET optimizer;
-- two-phase aggregates must agree with single-segment result
SELECT (SELECT round(ST_Area(ST_Union(geom))::numeric,6) FROM smoke_polys)
     = (SELECT round(ST_Area(ST_Union(geom))::numeric,6) FROM (SELECT geom FROM smoke_polys ORDER BY id) s) AS union_order_independent;
SELECT ST_MemUnion(geom) IS NOT NULL FROM smoke_polys;
SELECT count(DISTINCT cid) > 0 FROM (SELECT ST_ClusterDBSCAN(geom, 1, 1) OVER () AS cid FROM smoke_polys) s;

-- geography
SELECT round(ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(0,0),4326)::geography)) > 0 FROM smoke_pts WHERE id=1;
SELECT count(*) FROM smoke_pts WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(0,0),4326)::geography, 1500000);

-- proj
SELECT ST_AsText(ST_Transform(ST_SetSRID(ST_MakePoint(10,50),4326), 3857));
SELECT round(ST_X(ST_Transform(geom,3857))) IS NOT NULL FROM smoke_pts WHERE id=2;

-- geos
SELECT ST_IsValid(geom), ST_IsValidReason(geom) FROM smoke_polys WHERE id=1;
SELECT ST_AsText(ST_Simplify(ST_Buffer(ST_MakePoint(0,0),1),0.5));
SELECT ST_AsText(ST_VoronoiPolygons(ST_Collect(geom))) IS NOT NULL FROM smoke_pts WHERE id < 10;

-- ---------------------------------------------------------------- raster
CREATE TABLE smoke_rast (id int, rast raster) DISTRIBUTED BY (id);
INSERT INTO smoke_rast SELECT i, ST_AddBand(ST_MakeEmptyRaster(10,10,i*10,0,1,-1,0,0,4326),'8BUI'::text,i,0) FROM generate_series(1,20) i;
SELECT count(*) AS rows, count(DISTINCT gp_segment_id) AS segments_used FROM smoke_rast;
-- RASTER_send/RASTER_recv (branch commit 3d24b53c6): binary round trip
SELECT bool_and(ST_RastFromWKB(ST_AsWKB(rast)) = rast) FROM smoke_rast;
SELECT bool_and(ST_Width(rast)=10 AND ST_Height(rast)=10 AND ST_SRID(rast)=4326) FROM smoke_rast;
SELECT id, (ST_SummaryStats(rast)).mean FROM smoke_rast ORDER BY id LIMIT 3;
-- ST_Union aggregate across segments (raster moves through motion)
SELECT ST_Width(ST_Union(rast)), ST_Height(ST_Union(rast)), (ST_SummaryStats(ST_Union(rast))).count FROM smoke_rast;
SELECT ST_SameAlignment(rast) FROM smoke_rast;
SELECT ST_NotSameAlignmentReason(a.rast, b.rast) FROM smoke_rast a, smoke_rast b WHERE a.id=1 AND b.id=2;
SELECT (ST_MetaData(rast)).* FROM smoke_rast WHERE id=1;
SELECT ST_AsText(ST_Envelope(rast)) FROM smoke_rast WHERE id=1;
SELECT ST_Value(rast, 1, 1, 1) FROM smoke_rast WHERE id=5;
SELECT ST_Count(ST_MapAlgebra(rast, 1, '16BUI', '[rast]*2')) FROM smoke_rast WHERE id=1;
SELECT ST_Count(ST_Clip(rast, ST_MakeEnvelope(10,-5,15,0,4326))) FROM smoke_rast WHERE id=1;
SELECT (ST_DumpAsPolygons(rast)).val FROM smoke_rast WHERE id=3 LIMIT 1;
SELECT ST_Count(ST_AsRaster(geom, 0.5, 0.5)) > 0 FROM smoke_polys WHERE id=1;
SELECT ST_Count(ST_Tile(rast, 5, 5)) FROM smoke_rast WHERE id=1 LIMIT 1;
SELECT AddRasterConstraints('smoke_rast'::name, 'rast'::name);
SELECT r_table_name, srid, scale_x, scale_y, blocksize_x, blocksize_y, same_alignment, regular_blocking, num_bands, pixel_types FROM raster_columns WHERE r_table_name='smoke_rast';
SELECT DropRasterConstraints('smoke_rast'::name, 'rast'::name);
-- GDAL output drivers are DISABLE_ALL by default; the SET must reach the segments too
SET postgis.gdal_enabled_drivers = 'GTiff PNG';
SELECT ST_Count(ST_FromGDALRaster(ST_AsGDALRaster(rast, 'GTiff'))) FROM smoke_rast WHERE id=1;
SELECT length(ST_AsPNG(rast)) > 0 FROM smoke_rast WHERE id=2;
SELECT count(*) > 0 FROM ST_GDALDrivers();
RESET postgis.gdal_enabled_drivers;

-- ---------------------------------------------------------------- address standardizer
SELECT * FROM standardize_address('us_lex','us_gaz','us_rules', 'One Devonshire Place, PH 301', 'Boston, MA 02109');
SELECT * FROM standardize_address('us_lex','us_gaz','us_rules', '123 Main Street, Springfield, IL 62701');

-- ---------------------------------------------------------------- catalog views & helper funcs
SELECT count(*) FROM geometry_columns WHERE f_table_name LIKE 'smoke_%';
SELECT Find_SRID('public','smoke_pts','geom');
SELECT UpdateGeometrySRID('public','smoke_polys','geom',4326);
SELECT Populate_Geometry_Columns('public.smoke_pts'::regclass);

-- ---------------------------------------------------------------- dump / restore friendly output
\copy (SELECT id, ST_AsEWKT(geom) FROM smoke_polys ORDER BY id LIMIT 5) TO STDOUT

-- ---------------------------------------------------------------- teardown: everything must drop cleanly
DROP TABLE smoke_pts, smoke_polys, smoke_rast;
DROP EXTENSION address_standardizer_data_us;
DROP EXTENSION address_standardizer;
DROP EXTENSION postgis_raster;
DROP EXTENSION postgis;
SELECT extname FROM pg_extension ORDER BY 1;
EOSQL
  cat > "${LOGDIR}/smoke-tiger.sql" <<'EOSQL'
\set ON_ERROR_STOP on
\set ECHO queries
\timing off
-- postgis_tiger_geocoder (product scope). The whpg7 GPDB adaptations of
-- extras/tiger_geocoder (DISTRIBUTED clauses, GPDB-compatible PK/UNIQUE sets,
-- list-partitioned edges/faces/featnames/addr/zip_state, plpython3u
-- loader_generate_script) are re-applied on whpg19; the extension now
-- requires plpython3u, hence CASCADE.
CREATE EXTENSION postgis_tiger_geocoder CASCADE;
SELECT extname, extversion FROM pg_extension WHERE extname IN ('postgis_tiger_geocoder','fuzzystrmatch','plpython3u') ORDER BY 1;
SELECT pprint_addy(normalize_address('1 Devonshire Place, Boston, MA 02109'));
SELECT pprint_addy(normalize_address('28 Derby Street, Salem, MA 01970'));
SELECT os FROM tiger.loader_platform ORDER BY os;
SELECT count(*) FROM tiger.state_lookup;
SELECT count(*) FROM tiger.loader_lookuptables;
-- plpython3u loader script generation (tables empty, must still produce a script)
SELECT length(loader_generate_nation_script('sh')) > 0 AS nation_script;
SELECT length(loader_generate_script(ARRAY['MA'], 'sh')) > 0 AS state_script;
-- every tiger table must have a distribution policy GPDB accepted
SELECT c.relname, p.policytype, c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN gp_distribution_policy p ON p.localoid=c.oid WHERE n.nspname='tiger' AND c.relkind IN ('r','p') AND c.relname NOT LIKE 'list_%' ORDER BY 1;
SELECT count(*) AS partitions FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='tiger' AND c.relname LIKE 'list_%_part_%';
DROP EXTENSION postgis_tiger_geocoder;
DROP EXTENSION fuzzystrmatch;
DROP EXTENSION plpython3u;
DROP SCHEMA tiger;  -- CREATE EXTENSION creates it, DROP EXTENSION leaves it (upstream behaviour)
SELECT nspname FROM pg_namespace WHERE nspname IN ('tiger','tiger_data');
EOSQL
  cat > "${LOGDIR}/smoke-topology.sql" <<'EOSQL'
\set ON_ERROR_STOP on
\set ECHO queries
\timing off
-- topology (NOT in the WHPG product build: whpg/CMakeLists.txt configures --without-topology)
CREATE EXTENSION postgis_topology;
SELECT postgis_topology_scripts_installed();
SELECT topology.CreateTopology('smoke_topo', 4326);
SELECT topology.TopoGeo_AddLineString('smoke_topo', ST_GeomFromText('LINESTRING(0 0, 10 0, 10 10, 0 10, 0 0)',4326));
SELECT topology.TopoGeo_AddLineString('smoke_topo', ST_GeomFromText('LINESTRING(0 5, 10 5)',4326));
SELECT topology.TopoGeo_AddPoint('smoke_topo', ST_GeomFromText('POINT(5 2)',4326));
SELECT (SELECT count(*) FROM smoke_topo.node) nodes, (SELECT count(*) FROM smoke_topo.edge) edges, (SELECT count(*) FROM smoke_topo.face WHERE face_id>0) faces;
SELECT * FROM topology.ValidateTopology('smoke_topo');
SELECT topology.TopologySummary('smoke_topo');
CREATE TABLE smoke_land (id serial PRIMARY KEY, name text) DISTRIBUTED BY (id);
SELECT topology.AddTopoGeometryColumn('smoke_topo', 'public', 'smoke_land', 'tg', 'POLYGON');
INSERT INTO smoke_land (name, tg) VALUES ('a', topology.toTopoGeom(ST_GeomFromText('POLYGON((0 0,10 0,10 5,0 5,0 0))',4326), 'smoke_topo', 1));
SELECT ST_AsText(tg::geometry) FROM smoke_land;
SELECT topology.DropTopoGeometryColumn('public','smoke_land','tg');
SELECT topology.DropTopology('smoke_topo');
DROP TABLE smoke_land;
DROP EXTENSION postgis_topology;
SELECT nspname FROM pg_namespace WHERE nspname IN ('topology','smoke_topo');
EOSQL
  cat > "${LOGDIR}/smoke-sfcgal.sql" <<'EOSQL'
\set ON_ERROR_STOP on
\set ECHO queries
\timing off
-- sfcgal (NOT in the WHPG product build: whpg/CMakeLists.txt has no --with-sfcgal)
CREATE EXTENSION postgis_sfcgal;
SELECT postgis_sfcgal_full_version();
SELECT CG_3DArea(ST_GeomFromText('POLYGON((0 0 0,1 0 0,1 1 0,0 1 0,0 0 0))'));
SELECT ST_AsText(CG_Tesselate(ST_GeomFromText('POLYGON((0 0,1 0,1 1,0 1,0 0))')));
SELECT ST_AsText(CG_StraightSkeleton(ST_GeomFromText('POLYGON((0 0,4 0,4 4,0 4,0 0))'))) IS NOT NULL;
SELECT CG_Volume(CG_Extrude(ST_GeomFromText('POLYGON((0 0,1 0,1 1,0 1,0 0))'),0,0,1));
DROP EXTENSION postgis_sfcgal;
EOSQL
  rm -f "${LOGDIR}/smoke.sql"
  {
    echo "### $(ts) smoke on db ${db}"
    psql -X -c "DROP DATABASE IF EXISTS ${db}" && psql -X -c "CREATE DATABASE ${db}" || { echo "!! cannot create ${db}"; exit 1; }
    echo; echo "######## smoke-core (product scope)"
    psql -X -d "${db}" -f "${LOGDIR}/smoke-core.sql"; echo "psql core rc=$?"
    psql -X -d "${db}" -c "CREATE EXTENSION IF NOT EXISTS postgis" >/dev/null
    echo; echo "######## smoke-tiger (product scope)"
    psql -X -d "${db}" -f "${LOGDIR}/smoke-tiger.sql"; echo "psql tiger rc=$?"
    echo; echo "######## smoke-topology (out of product scope)"
    psql -X -d "${db}" -f "${LOGDIR}/smoke-topology.sql"; echo "psql topology rc=$?"
    echo; echo "######## smoke-sfcgal (out of product scope)"
    psql -X -d "${db}" -f "${LOGDIR}/smoke-sfcgal.sql"; echo "psql sfcgal rc=$?"
    psql -X -d "${db}" -c "DROP EXTENSION IF EXISTS postgis CASCADE" >/dev/null 2>&1
  } 2>&1 | tee "${log}"
  rc_core=$(grep -E '^psql core rc=' "${log}" | tail -1 | sed 's/.*rc=//');     rc_core="${rc_core:-1}"
  rc_topo=$(grep -E '^psql topology rc=' "${log}" | tail -1 | sed 's/.*rc=//'); rc_topo="${rc_topo:-1}"
  rc_sfc=$(grep -E '^psql sfcgal rc=' "${log}" | tail -1 | sed 's/.*rc=//');    rc_sfc="${rc_sfc:-1}"
  rc_tiger=$(grep -E '^psql tiger rc=' "${log}" | tail -1 | sed 's/.*rc=//');  rc_tiger="${rc_tiger:-1}"
  rc="${rc_core}"; [ "${rc_tiger}" -ne 0 ] && rc=1
  if [ "${rc}" -eq 0 ]; then psql -X -c "DROP DATABASE ${db}" >/dev/null; else echo "!! core smoke failed; db ${db} kept for inspection" | tee -a "${log}"; fi
  result smoke "${rc}" "core rc=${rc_core}; tiger rc=${rc_tiger}; out-of-scope: topology rc=${rc_topo}, sfcgal rc=${rc_sfc}; $(grep -c 'ERROR:' "${log}") ERROR line(s), see smoke.log"
  return "${rc}"
}

###############################################################################
phase_base() {
  local log="${LOGDIR}/installcheck-base.log" rc=0
  export PGIS_REG_TMPDIR="/tmp/pgis_reg_base"
  rm -rf "${PGIS_REG_TMPDIR}"
  {
    echo "### $(ts) make installcheck-base RUNTESTFLAGS='${RUNTESTFLAGS}'"
    cd "${SRCDIR}" && make installcheck-base RUNTESTFLAGS="${RUNTESTFLAGS}"; rc=$?
    echo "make rc=${rc}"
  } 2>&1 | tee "${log}"
  rc=$(grep -E '^make rc=' "${log}" | tail -1 | sed 's/make rc=//')
  save_regress_tmp base
  extract_failures "${log}" "${LOGDIR}/installcheck-base.failures.txt"
  result base "${rc}" "$(grep -cE ' failed' "${log}") failed test line(s), see installcheck-base.failures.txt"
  return "${rc}"
}

###############################################################################
phase_upgrade() {
  local log="${LOGDIR}/installcheck-upgrade.log" rc=0
  export PGIS_REG_TMPDIR="/tmp/pgis_reg_upgrade"
  rm -rf "${PGIS_REG_TMPDIR}"
  {
    echo "### $(ts) make installcheck-upgrade RUNTESTFLAGS='${RUNTESTFLAGS}'"
    # installcheck-upgrade runs its three paths as recipe lines of one target, so the
    # first failure (even an out-of-scope sfcgal diff) skips the rest. Run them one by one.
    rc=0
    cd "${SRCDIR}" || exit 1
    for t in installcheck-upgrade-from-unpackaged installcheck-upgrade-from-unpackaged-by-func installcheck-upgrade-from-packaged-by-func; do
      echo; echo "######## ${t}"
      make "${t}" RUNTESTFLAGS="${RUNTESTFLAGS}"; r=$?; echo "${t} rc=${r}"; [ "${r}" -ne 0 ] && rc=1
    done
    echo "make rc=${rc}"
  } 2>&1 | tee "${log}"
  rc=$(grep -E '^make rc=' "${log}" | tail -1 | sed 's/make rc=//')
  save_regress_tmp upgrade
  extract_failures "${log}" "${LOGDIR}/installcheck-upgrade.failures.txt"
  result upgrade "${rc}" "$(grep -cE ' failed' "${log}") failed test line(s), see installcheck-upgrade.failures.txt"
  return "${rc}"
}

###############################################################################
note "=== validate_whpg19.sh start; phases: ${PHASES[*]}"
overall=0
for p in "${PHASES[@]}"; do
  case "$p" in
    preflight|install|rebuild|smoke|base|upgrade) "phase_${p}" || overall=1 ;;
    *) note "unknown phase: $p"; overall=1 ;;
  esac
done
note "=== done (overall rc=${overall}); logs in ${LOGDIR}"
exit "${overall}"
