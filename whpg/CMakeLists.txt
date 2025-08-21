# Only static link is supported by now. But it won't be difficult to support
# dynamic link.
# NOTE: For the static link, the order of '-l' matters!!! If you meet strange
# linking issues, try to reorder the '-l' arguments.
# Postgis has quite some dependencies, we use static link to handle the
# libraries. But it also requires some data files from gdal and proj for some
# features. proj and gdal has env 'GDAL_DATA' and 'PROJ_LIB' to set the
# directories at run-time. But they also hard-code those directories with the
# 'prefix' during the compiling time, which means, if we make sure the those
# directories ("$prefix/share/gdal" and "$prefix/share/proj") don't change after
# installation, no envs are needed. To achieve that together with the static
# link, we use 'DCMAKE_STAGING_PREFIX' trick and 'sed' to replace the prefix for
# compiling.
cmake_minimum_required(VERSION 3.14)
project(postgis-whpg)

include(ExternalProject)

if(NOT CMAKE_BUILD_TYPE)
    message(STATUS "Setting build type to 'Release' as none was specified.")
    set(CMAKE_BUILD_TYPE "Release" CACHE
        STRING "Choose the type of build." FORCE)
endif()
if (CMAKE_BUILD_TYPE STREQUAL "Debug")
set(CONFIGURE_ENABLE_DEBUG --enable-debug)
endif()

if(DEFINED ENV{GPHOME})
    set(GPHOME_DIR "$ENV{GPHOME}")
    message(STATUS "Use '${GPHOME_DIR}' as GPHOME")
else()
    message(FATAL_ERROR
        "Error: The GPHOME environment variable is not set."
        "Please set it to your Greenplum Database installation path before"
        "running cmake.")
endif()

# For the local dev build, set this to the $GPHOME.
# proj and gdal should use `/usr/local/greenplum-db` as the prefix, to make
# sure it can find the `share/proj` and `share/gdal` at runtime.
if(NOT PROJ_GDAL_PREFIX)
    set(PROJ_GDAL_PREFIX /usr/local/greenplum-db)
    message(STATUS
        "gdal and proj will use '${PROJ_GDAL_PREFIX}' as the prefix.")
endif()
# For the cmake install target
set(CMAKE_INSTALL_PREFIX ${GPHOME_DIR})

set(INSTALL_DIR ${CMAKE_BINARY_DIR}/usr)
set(DOWNLOAD_DIR ${CMAKE_SOURCE_DIR}/3rdparty/download)
set(POSTGIS_TEMP_INSTALL_PREFIX ${CMAKE_BINARY_DIR}/postgis_temp_install)
set(PATCH_DIR ${CMAKE_SOURCE_DIR}/3rdparty)
set(POSTGIS_SOURCE_DIR ${CMAKE_SOURCE_DIR}/..)
# Increase this if you have a powerful machine
if(NOT JOBS)
    set(JOBS 4)
endif()

ExternalProject_Add(
    proj

    URL
    https://download.osgeo.org/proj/proj-8.2.1.tar.gz
    URL_HASH
    SHA256=76ed3d0c3a348a6693dfae535e5658bbfd47f71cb7ff7eb96d9f12f7e068b1cf
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    PATCH_COMMAND
    patch -p1 < ${PATCH_DIR}/proj-add-missing-cstdint-includes.patch

    CMAKE_ARGS
    "-DBUILD_SHARED_LIBS=OFF"
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    "-DCMAKE_INSTALL_PREFIX=${PROJ_GDAL_PREFIX}"
    "-DCMAKE_STAGING_PREFIX=${INSTALL_DIR}"
    "-DENABLE_CURL=OFF"
    "-DBUILD_TESTING=OFF"
    "-DBUILD_PROJSYNC=OFF"
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND
    make install
    COMMAND
    sed -i "s|prefix=${PROJ_GDAL_PREFIX}|prefix=${INSTALL_DIR}|g" ${INSTALL_DIR}/lib64/pkgconfig/proj.pc
    # Workaround el8 find libproj issue. postgis hardcode it to 'prefix/lib'
    COMMAND
    mkdir -p ${INSTALL_DIR}/lib &&
    ln -s ${INSTALL_DIR}/lib64/libproj.a ${INSTALL_DIR}/lib
)

ExternalProject_Add(
    geos

    URL
    https://download.osgeo.org/geos/geos-3.10.2.tar.bz2
    URL_HASH
    SHA256=50bbc599ac386b4c2b3962dcc411f0040a61f204aaef4eba7225ecdd0cf45715
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    PATCH_COMMAND
    patch -p1 < ${PATCH_DIR}/geos-add-missing-cstdint-includes.patch

    CMAKE_ARGS
    "-DBUILD_SHARED_LIBS=OFF"
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    "-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}"
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND make install
    COMMAND patch -f ${INSTALL_DIR}/bin/geos-config
    ${PATCH_DIR}/geos-config.patch
)

ExternalProject_Add(
    libxml2

    URL
    https://download.gnome.org/sources/libxml2/2.7/libxml2-2.7.2.tar.xz
    URL_HASH
    SHA256=751c3502cef900b9532521b42728ea77feef3c932b5e475b3d898e363c8c717a
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    BUILD_IN_SOURCE YES
    CONFIGURE_COMMAND
    ${CMAKE_COMMAND} -E env
    "CFLAGS=-fPIC"
    <SOURCE_DIR>/configure
    --prefix=${INSTALL_DIR}
    --enable-shared=no
    --without-threads
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND make install
)


ExternalProject_Add(
    json-c

    URL
    https://github.com/json-c/json-c/archive/refs/tags/json-c-0.18-20240915.tar.gz
    URL_HASH
    SHA256=3112c1f25d39eca661fe3fc663431e130cc6e2f900c081738317fba49d29e298
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    CMAKE_ARGS
    "-DBUILD_SHARED_LIBS=OFF"
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    "-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}"
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    "-DCMAKE_POLICY_VERSION_MINIMUM=${CMAKE_POLICY_VERSION_MINIMUM}"
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND make install
)

ExternalProject_Add(
    gdal

    URL
    https://download.osgeo.org/gdal/3.6.3/gdal-3.6.3.tar.gz
    URL_HASH
    SHA256=1c271c08b7161227384833ddc24febd8d012a44c6de93a5912051784e3247506
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    # "-DGDAL_ENABLE_DRIVER_PDF=OFF"
    # Turns off the PDF support, which doesn't compile with higher version gcc.
    # Postgis doesn't need it anyway.
    CMAKE_ARGS
    "-DCMAKE_POLICY_VERSION_MINIMUM=${CMAKE_POLICY_VERSION_MINIMUM}"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DCMAKE_C_FLAGS='-fPIC'"
    "-DCMAKE_CXX_FLAGS='-fPIC'"
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    "-DBASH_COMPLETIONS_DIR="
    "-DCMAKE_INSTALL_PREFIX=${PROJ_GDAL_PREFIX}"
    "-DCMAKE_STAGING_PREFIX=${INSTALL_DIR}"
    "-DGDAL_ENABLE_DRIVER_PDF=OFF"
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    BUILD_COMMAND make -j${JOBS}

    INSTALL_COMMAND
    make install
    COMMAND
    sed -i "s|${PROJ_GDAL_PREFIX}|${INSTALL_DIR}|g" ${INSTALL_DIR}/bin/gdal-config
    COMMAND
    patch ${INSTALL_DIR}/bin/gdal-config ${PATCH_DIR}/gdal-config.patch

    DEPENDS libxml2 json-c geos proj
)

ExternalProject_Add(
    postgis

    SOURCE_DIR ${POSTGIS_SOURCE_DIR}

    CONFIGURE_COMMAND
    ./autogen.sh
    COMMAND
    ${CMAKE_COMMAND} -E env
    "CFLAGS=-std=gnu99 -fPIC -Wno-error=int-conversion"
    # NOTE: Due to linker's strange behaviour, without putting -ltiff and
    # -lsqlite3 before other static libs, the final so won't be linking to the
    # so libs.
    # -L${GPHOME_DIR}/lib is for linking WHPG's libpq
    # -ldl workaround el8 -lproj test
    "LDFLAGS=-lm -lstdc++ -ldl -ltiff -L${GPHOME_DIR}/lib -L${INSTALL_DIR}/lib -lsqlite3 -L${INSTALL_DIR}/lib64"
    <SOURCE_DIR>/configure
    --prefix=${GPHOME_DIR}
    --exec-prefix=${GPHOME_DIR}
    --with-pgconfig=${GPHOME_DIR}/bin/pg_config
    --with-projdir=${INSTALL_DIR}
    --with-geosconfig=${INSTALL_DIR}/bin/geos-config
    --with-gdalconfig=${INSTALL_DIR}/bin/gdal-config
    --with-xml2config=${INSTALL_DIR}/bin/xml2-config
    --with-jsondir=${INSTALL_DIR}
    --with-raster
    --without-topology
    --without-protobuf
    ${CONFIGURE_ENABLE_DEBUG}
    BUILD_COMMAND
    make -j${JOBS} with_llvm=no
    INSTALL_COMMAND
    make install DESTDIR=${POSTGIS_TEMP_INSTALL_PREFIX}
    with_llvm=no
    BUILD_IN_SOURCE YES

    DEPENDS proj geos gdal libxml2 json-c
)

add_custom_target(
    installcheck-postgis
    ${CMAKE_COMMAND} -E env
    "RUNTESTFLAGS=-v --extension=plpython3u"
    # TODO: enable the upgrade test
    make installcheck-base with_llvm=no
    WORKING_DIRECTORY ${POSTGIS_SOURCE_DIR}
    DEPENDS postgis
)

install(DIRECTORY ${INSTALL_DIR}/share/proj TYPE DATA)
install(DIRECTORY ${INSTALL_DIR}/share/gdal TYPE DATA)
install(DIRECTORY
    ${POSTGIS_TEMP_INSTALL_PREFIX}${GPHOME_DIR}/bin/ TYPE BIN)
install(DIRECTORY
    ${POSTGIS_TEMP_INSTALL_PREFIX}${GPHOME_DIR}/share/ TYPE DATA)
install(DIRECTORY
    ${POSTGIS_TEMP_INSTALL_PREFIX}${GPHOME_DIR}/lib/ TYPE LIB)
