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
