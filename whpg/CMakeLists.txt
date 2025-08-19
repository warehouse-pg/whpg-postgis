# Only static link is supported by now. But it won't be difficult to support
# dynamic link.
# NOTE: For the static link, the order of '-l' matters!!! If you meet strange
# linking issues, try to reorder the '-l' arguments.
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
    https://download.osgeo.org/proj/proj-5.2.0.tar.gz
    URL_HASH
    SHA256=ef919499ffbc62a4aae2659a55e2b25ff09cccbbe230656ba71c6224056c7e60
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    CONFIGURE_COMMAND
    ${CMAKE_COMMAND} -E env
    "CFLAGS=-fPIC"
    <SOURCE_DIR>/configure --prefix=${PROJ_GDAL_PREFIX} --enable-shared=no
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND make install prefix=${INSTALL_DIR}
)

ExternalProject_Add(
    geos

    URL
    https://download.osgeo.org/geos/geos-3.10.2.tar.bz2
    URL_HASH
    SHA256=50bbc599ac386b4c2b3962dcc411f0040a61f204aaef4eba7225ecdd0cf45715
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    CMAKE_ARGS
    "-DBUILD_SHARED_LIBS=OFF"
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    "-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}"
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND make install
    COMMAND patch ${INSTALL_DIR}/bin/geos-config ${PATCH_DIR}/geos-config.patch
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
    https://s3.amazonaws.com/json-c_releases/releases/json-c-0.12.1.tar.gz
    URL_HASH
    SHA256=2a136451a7932d80b7d197b10441e26e39428d67b1443ec43bbba824705e1123
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    #-Wno-error=calloc-transposed-args
    BUILD_IN_SOURCE YES
    CONFIGURE_COMMAND
    ${CMAKE_COMMAND} -E env
    "CFLAGS=-fPIC -Wno-error=implicit-fallthrough"
    <SOURCE_DIR>/configure --prefix=${INSTALL_DIR} --enable-shared=no
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND make install
)

ExternalProject_Add(
    gdal

    URL
    https://download.osgeo.org/gdal/2.4.4/gdal-2.4.4.tar.gz
    URL_HASH
    SHA256=e6a2456907610639d73fc6a82bb10aa6fa02e2d03b24edacde34a16b6aa91080
    DOWNLOAD_DIR ${DOWNLOAD_DIR}

    PATCH_COMMAND
    patch <SOURCE_DIR>/ogr/ogrsf_frmts/cad/libopencad/dwg/r2000.cpp
    ${PATCH_DIR}/gdal-r2000.cpp.patch
    COMMAND
    patch <SOURCE_DIR>/configure
    ${PATCH_DIR}/gdal-configure.patch

    BUILD_IN_SOURCE YES
    CONFIGURE_COMMAND
    ${CMAKE_COMMAND} -E env
    "LDFLAGS=-lm -lstdc++"
    "CFLAGS=-fPIC"
    "CXXFLAGS=-fPIC"
    <SOURCE_DIR>/configure
    --prefix=${PROJ_GDAL_PREFIX}
    --enable-shared=no
    --with-xml2=${INSTALL_DIR}/bin/xml2-config
    --with-libjson-c=${INSTALL_DIR}
    --with-geos=${INSTALL_DIR}/bin/geos-config
    --without-jasper
    --without-hdfs
    --without-hdf4
    --without-hdf5
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND make install prefix=${INSTALL_DIR}
    COMMAND
    patch ${INSTALL_DIR}/bin/gdal-config ${PATCH_DIR}/gdal-config.patch
    COMMAND
    sed -i "s|${PROJ_GDAL_PREFIX}|${INSTALL_DIR}|g" ${INSTALL_DIR}/bin/gdal-config

    DEPENDS libxml2 json-c geos
)

ExternalProject_Add(
    postgis

    SOURCE_DIR ${POSTGIS_SOURCE_DIR}

    CONFIGURE_COMMAND
    ./autogen.sh
    COMMAND
    ${CMAKE_COMMAND} -E env
    "CFLAGS=-std=gnu99 -fPIC"
    "LDFLAGS=-lm -lstdc++ -ltiff -L${GPHOME_DIR}/lib "
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
    BUILD_COMMAND make -j${JOBS}
    INSTALL_COMMAND
    make install DESTDIR=${POSTGIS_TEMP_INSTALL_PREFIX}
    BUILD_IN_SOURCE YES

    DEPENDS proj geos gdal libxml2 json-c
)

add_custom_target(
    installcheck-postgis
    RUNTESTFLAGS="--verbose" make test
    WORKING_DIRECTORY ${POSTGIS_SOURCE_DIR}/regress
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
install(DIRECTORY
    ${POSTGIS_TEMP_INSTALL_PREFIX}${GPHOME_DIR}/include/ TYPE INCLUDE)
