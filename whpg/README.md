The `CMakeLists.txt` in this directory enables the static link of the extension.

# Build dependencies

- `prec-devel` is needed for `address_standardizer` extension.
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


```

From the source root directory

```
RUNTESTFLAGS="-v --extension=plpython3u" make installcheck
```
