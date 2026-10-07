# WarehousePG PostGIS

## Introduction

PostGIS extends a distributed database like WarehousePG with support for
geographic objects, allowing location queries to be run in SQL. It adds
geometry, geography and raster types, spatial indexes, and hundreds of
functions for spatial analysis and processing, together with the TIGER
geocoder and, when PCRE is available at build time, address standardization.
The topology extension is not built.

This repository is a fork of the open-source Greenplum PostGIS project
(github.com/greenplum-db/geospatial, no longer public), renamed to whpg-postgis
and maintained for WarehousePG. Each WarehousePG line has its own branch, based
on an upstream PostGIS stable release (https://github.com/postgis/postgis) with
the Greenplum and WarehousePG changes on top:

| Branch   | WarehousePG | PostGIS |
|----------|-------------|---------|
| `whpg6`  | 6           | 2.5.x   |
| `whpg7`  | 7           | 3.3.x   |
| `whpg19` | 19          | 3.6.x   |

This is the `whpg7` branch: PostGIS 3.3.8, based on upstream `stable-3.3`, for
WarehousePG 7.

## Building and Testing

The CMake build in [`whpg`](whpg) builds PostGIS together with its bundled
dependencies (proj, geos, gdal, libxml2 and json-c) and links them statically.
libtiff, sqlite3 and PCRE come from the system and must be installed on both the
build and the runtime hosts; `address_standardizer` is built only when PCRE is
found.

`GPHOME` must point to your WarehousePG installation. proj and gdal look for
their `share/proj` and `share/gdal` data under `PROJ_GDAL_PREFIX`, which
defaults to `/usr/local/greenplum-db`. If WarehousePG is installed elsewhere,
run `cmake -DPROJ_GDAL_PREFIX=$GPHOME ../whpg` instead of `cmake ../whpg`.

```
mkdir build
cd build
cmake ../whpg
make
make install                  # may need root to write into $GPHOME
make installcheck-postgis     # needs a running WarehousePG cluster
```

See [`whpg/README.md`](whpg/README.md) for build dependencies and other ways
to build and test.

## Documentation

* Upstream readme: [README.postgis](README.postgis)
* PostGIS manuals: https://postgis.net/documentation
* Release notes: [NEWS](NEWS)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE-OF-CONDUCT.md). To report a security issue, see
[SECURITY.md](SECURITY.md).

## License

GNU General Public License, version 2 or later, with some files under other
licenses. See [LICENSE.md](LICENSE.md).

## Credits

PostGIS is developed by the PostGIS Project Steering Committee and many
contributors; see [CREDITS](CREDITS) and https://postgis.net/.
