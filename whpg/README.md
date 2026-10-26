The `CMakeLists.txt` in this directory enables the static link of the extension.

# Build dependencies

- `pcre-devel` is needed for `address_standardizer` extension.
- `sqlite-devel` and the `sqlite` CLI are needed to build the vendored PROJ
  (it generates `proj.db` at build time and links `libsqlite3`).
- `libtiff-devel` is needed to build the vendored GDAL, and the matching
  runtime library to load the extension.
- Remember to install `cmake`, `autoconf`, `patch` and other normal development packages to build.

# Vendored dependencies

The static build downloads and compiles these libraries (pinned by URL and
SHA256 in `CMakeLists.txt`):

| Library | Version | Why this version |
|---------|---------|------------------|
| PROJ    | 7.2.1   | Last release that ships `proj_api.h`; PostGIS 2.5 (this branch) still uses the PROJ.4 API. PROJ 8 drops it. |
| GEOS    | 3.10.2  | Unchanged, same as the whpg7 branch. The `regress` expectations on this branch were adjusted for 3.10.2; 3.10.7 changes `ST_Boundary` Z values, relate matrices under boundary-node rules and the overlay error texts (`boundary`, `relate_bnr`, `tickets` fail), so a bump needs the expected outputs refreshed first. |
| GDAL    | 3.6.4   | Same line as the whpg7 branch; GDAL >= 3.5 needs PROJ >= 6.3, which rules out the old PROJ 5. |
| libxml2 | 2.13.9  | Current maintained 2.13 line. Built without python, lzma and threads: PostGIS only needs the parser. |
| json-c  | 0.18    | Same as the whpg7 branch (CMake build, static, PIC). |

Keeping them current is part of this branch's maintenance:

1. Watch the upstream advisories (GEOS/GDAL/PROJ: OSGeo release notes and
   `NEWS`; libxml2: GNOME GitLab releases; json-c: GitHub releases) and the
   RHEL/EPEL CVE feeds for these five packages, since the statically linked
   copies do not get OS-level patches.
2. To bump one: change the `URL` and `URL_HASH` in `CMakeLists.txt`
   (`sha256sum` of the downloaded tarball), update the table above, and if
   the library's `*-config` script changed, refresh the matching patch in
   `3rdparty/`.
3. Verify with the packaging pipeline (`postgis-release.yml` in
   `EnterpriseDB/whpg-extensions-packaging` with `whpg-version=6.x`): it
   builds the static bundle on x86_64 and runs `make installcheck-postgis`
   against a real cluster.

# Build

```
# Create the build directory
mkdir build
# Run cmake, the $GPHOME needs to be set first
cmake ../whpg
# Build the extensions
make
```

# Install the extension

From the build directory, install both postgis and dependencies:

```
cd build
make install
```

From the source root directory, this won't install the dependencies:

```
make install
```

# Run tests

From the build directory:

```
cd build
make installcheck-postgis
```

From the source root directory

```
make -C regress test
```
