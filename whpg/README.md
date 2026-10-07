The `CMakeLists.txt` in this directory enables the static link of the extension.

# Build dependencies

- `pcre-devel` is needed for `address_standardizer` extension.
- `libtiff-devel` and `sqlite-devel` are needed to build, and the matching runtime libraries
  to load the extension.
- Remember to install `cmake`, `autoconf`, `patch` and other normal development packages to build.

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

From the build directory, this will install the dependencies as well:

```
cd build
make install
```

From the source root directory, this will only install postgis extension:

```
make install
```

# Run tests

From the build directory:

```
cd build
make installcheck-postgis
```

From the source root directory, running the same tests as the CMake target
(`make installcheck` would also run the upgrade tests, which the CMake target
does not run yet):

```
RUNTESTFLAGS="-v" make installcheck-base
```
