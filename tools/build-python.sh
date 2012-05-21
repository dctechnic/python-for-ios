#!/bin/bash

. $(dirname $0)/environment.sh

# credit to:
# http://randomsplat.com/id5-cross-compiling-python-for-embedded-linux.html
# http://latenitesoft.blogspot.com/2008/10/iphone-programming-tips-building-unix.html

# download python and patch if they aren't there
if [ ! -f $CACHEROOT/Python-$PYTHON_VERSION.tar.bz2 ]; then
    curl http://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tar.bz2 > $CACHEROOT/Python-$PYTHON_VERSION.tar.bz2
fi

echo "extracting"

# get rid of old build
rm -rf $TMPROOT/Python-$PYTHON_VERSION
try tar -xjf $CACHEROOT/Python-$PYTHON_VERSION.tar.bz2
try mv Python-$PYTHON_VERSION $TMPROOT
try pushd $TMPROOT/Python-$PYTHON_VERSION

# Patch Python for temporary reduce PY_SSIZE_T_MAX otherzise, splitting string doesnet work
try patch -p1 < $KIVYIOSROOT/src/python_files/Python-$PYTHON_VERSION-ssize-t-max.patch
try patch -p1 < $KIVYIOSROOT/src/python_files/Python-$PYTHON_VERSION-dynload.patch

# Copy our setup for modules
try cp $KIVYIOSROOT/src/python_files/ModulesSetup Modules/Setup.local


echo "== building for native machine ============================================"
echo "follow build log with 'tail -f ${LOG}'"

try ./configure CC="$CCACHE clang -Qunused-arguments -fcolor-diagnostics" >> "${LOG}" 2>&1
try make python.exe Parser/pgen >> "${LOG}" 2>&1
try mv python.exe hostpython
try mv Parser/pgen Parser/hostpgen
try make distclean >> "${LOG}" 2>&1

# patch python to cross-compile
try patch -p1 < $KIVYIOSROOT/src/python_files/Python-$PYTHON_VERSION-xcompile.patch


echo "== building for ios armv7 (iphone 3gs or newer) ==========================="

# set up environment variables for cross compilation
export CPPFLAGS="-I$SDKROOT/usr/lib/gcc/arm-apple-darwin11/4.2.1/include/ -I$SDKROOT/usr/include/"
export CPP="$CCACHE /usr/bin/cpp $CPPFLAGS"

# make a link to a differently named library for who knows what reason
mkdir extralibs-ios||echo "foo"
ln -s "$SDKROOT/usr/lib/libgcc_s.1.dylib" extralibs-ios/libgcc_s.10.4.dylib || echo "sdf"

# Copy our setup for modules
try cp $KIVYIOSROOT/src/python_files/ModulesSetup Modules/Setup.local

try ./configure CC="$ARM_CC" LD="$ARM_LD" \
	CFLAGS="$ARM_CFLAGS" LDFLAGS="$ARM_LDFLAGS -Lextralibs-ios/" \
	--disable-toolbox-glue \
	--host=armv7-apple-darwin \
	--prefix=/python \
	--without-doc-strings >> "${LOG}" 2>&1

try make HOSTPYTHON=./hostpython HOSTPGEN=./Parser/hostpgen \
     CROSS_COMPILE_TARGET=yes >> "${LOG}" 2>&1

try make install HOSTPYTHON=./hostpython CROSS_COMPILE_TARGET=yes prefix="$BUILDROOT/python" >> "${LOG}" 2>&1

try mv -f $BUILDROOT/python/lib/libpython2.7.a $BUILDROOT/lib/libpython2.7-armv7.a
make distclean >> "${LOG}" 2>&1
deduplicate $BUILDROOT/lib/libpython2.7-armv7.a


echo "== building for ios simulator ============================================="

export CPPFLAGS="-I$SDKROOT_SIMULATOR/usr/lib/gcc/arm-apple-darwin11/4.2.1/include/ -I$SDKROOT_SIMULATOR/usr/include/"
export CFLAGS="$CPPFLAGS -pipe -no-cpp-precomp -isysroot $SDKROOT_SIMULATOR"
export LDFLAGS="-isysroot $SDKROOT_SIMULATOR -Lextralibs-i386/"
export CPP="/usr/bin/cpp $CPPFLAGS"

# make a link to a differently named library for who knows what reason
mkdir extralibs-i386
ln -s "/usr/lib/libgcc_s.1.dylib" extralibs-i386/libgcc_s.10.4.dylib

./configure CC="$DEVROOT_SIMULATOR/usr/bin/i686-apple-darwin11-llvm-gcc-4.2 -m32" \
            LD="$DEVROOT_SIMULATOR/usr/bin/ld" --disable-toolbox-glue --host=i386-apple-darwin --prefix=/python >> "${LOG}" 2>&1

try make HOSTPYTHON=./hostpython HOSTPGEN=./Parser/hostpgen \
     CROSS_COMPILE_TARGET=yes >> "${LOG}" 2>&1

try make install HOSTPYTHON=./hostpython CROSS_COMPILE_TARGET=yes prefix="$BUILDROOT/python" >> "${LOG}" 2>&1

try mv -f $BUILDROOT/python/lib/libpython2.7.a $BUILDROOT/lib/libpython2.7-i386.a
deduplicate $BUILDROOT/lib/libpython2.7-i386.a


# create fat library
lipo -create -output $BUILDROOT/lib/libpython2.7.a $BUILDROOT/lib/libpython2.7-i386.a $BUILDROOT/lib/libpython2.7-armv7.a

echo "done. your static libraries are at:"
echo "build/lib/libpython2.7.a (fat)"
echo "build/lib/libpython2.7-armv7.a"
echo "build/lib/libpython2.7-i386.a"
