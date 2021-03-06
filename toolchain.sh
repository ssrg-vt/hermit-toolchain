#!/bin/bash
#
# script to build HermitCore's toolchain
#
# $1 = specifies the target architecture
# $2 = specifies the installation directory

BUILDDIR=build
CLONE_DEPTH="--depth=50"
PREFIX="$2"
TARGET=$1
NJOBS=-j"$(nproc)"
PATH=$PATH:$PREFIX/bin
ARCH_OPT="-mtune=native"
export CFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT"
export GOFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT"
export FCFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT"
export FFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT"
export CXXFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT"

export AS_FOR_TARGET="$PREFIX/bin/x86_64-hermit-as"
export CC_FOR_TARGET="$PREFIX/usr/local/bin/clang"

export PATH

# Checks prerequisites
res=`cmake --version | grep version | sed -rn "s/^cmake version ([0-9])\.([0-9]+)\.([0-9]+)$/\1\2/p"`
if [[ "$res" == "" || "$res" -lt "37" ]]; then
	echo "Please install cmake > 3.7"
	exit
fi

res=`which nasm`
if [ "$res" == "" ]; then
	echo "Please install nasm"
	exit 
fi

# Pierre: in some situations libomp fails to buld as it cannto find asm/errno.h
# this seems to solve the issue
if [ -d "/usr/include/asm" ]; then
	  echo "/usr/include/asm does not exist, trying to symlink from /usr/include/asm-generic"
	  sudo ln -s /usr/include/asm-generic /usr/include/asm
fi

echo "Build bootstrap toolchain for $TARGET with $NJOBS jobs for $PREFIX"
sleep 1

mkdir -p $BUILDDIR
cd $BUILDDIR

if [ ! -d "binutils" ]; then
git clone $CLONE_DEPTH https://github.com/RWTH-OS/binutils.git
fi


if [ ! -d "hermit-llvm" ]; then
git clone -b master https://github.com/ssrg-vt/hermit-llvm hermit-llvm
fi

if [ ! -d "gcc" ]; then
git clone $CLONE_DEPTH https://github.com/RWTH-OS/gcc.git
wget ftp://gcc.gnu.org/pub/gcc/infrastructure/isl-0.15.tar.bz2 -O isl-0.15.tar.bz2
tar jxf isl-0.15.tar.bz2
mv isl-0.15 gcc/isl
cd gcc 
cd ..
fi

if [ ! -d "hermit" ]; then
git clone --recursive -b llvm-stable https://github.com/ssrg-vt/HermitCore hermit
fi

if [ ! -d "newlib" ]; then
git clone -b  llvm-stable https://github.com/ssrg-vt/newlib
fi

if [ ! -d "pte" ]; then
git clone $CLONE_DEPTH https://github.com/RWTH-OS/pthread-embedded.git pte
cd pte
CC_FOR_TARGET="$PREFIX/usr/local/bin/clang" ./configure --target=$TARGET --prefix=$PREFIX
cd -
fi

if [ ! -d "tmp/llvm" ]; then
mkdir -p tmp/llvm
cd tmp/llvm
cmake -G "Unix Makefiles" ../../hermit-llvm && make $NJOBS
make install DESTDIR=$PREFIX
cd -
fi
#read -p "End of LLVM"


if [ ! -d "tmp/binutils" ]; then
mkdir -p tmp/binutils
cd tmp/binutils
../../binutils/configure --target=$TARGET --prefix=$PREFIX --with-sysroot --disable-multilib --disable-shared --disable-nls --disable-gdb --disable-libdecnumber --disable-readline --disable-sim --disable-libssp --enable-tls --enable-lto --enable-plugin && make $NJOBS && make install && echo "success"
cd -
fi
#read -p "End of Binutils"

if [ ! -d "tmp/bootstrap" ]; then
mkdir -p tmp/bootstrap
cd tmp/bootstrap
../../gcc/configure --target=$TARGET --prefix=$PREFIX --without-headers --disable-multilib --with-isl --enable-languages=c --disable-nls --disable-shared --disable-libssp --disable-libgomp --enable-threads=posix --enable-tls --enable-lto --disable-symvers && make $NJOBS all-gcc && make install-gcc && echo "success"
cd -
fi
#read -p "End of Bootstrap"

if [ ! -d "tmp/hermit" ]; then
mkdir -p tmp/hermit
cd tmp/hermit
cmake -DHERMIT_PREFIX=$PREFIX -DCMAKE_INSTALL_PREFIX=$PREFIX -DBOOTSTRAP=true ../../hermit
make hermit-bootstrap $NJOBS
make hermit-bootstrap-install && echo "success"
cd -
fi
#read -p "End of Hermit-Bootstrap"

if [ ! -d "tmp/newlib" ]; then
export CFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT -target x86_64-hermit"
mkdir -p tmp/newlib
cd tmp/newlib
CC="$PREFIX/usr/local/bin/clang" ../../newlib/configure --target=$TARGET --prefix=$PREFIX --disable-shared --disable-multilib --enable-lto --enable-newlib-hw-fp --enable-newlib-io-c99-formats --enable-newlib-multithread && make $NJOBS && make install && echo "success"
cd -
fi
#read -p "End of Newlib"

cd pte
CC_FOR_TARGET="$PREFIX/usr/local/bin/clang" make $NJOBS && make install && echo "success"
cd ..
#read -p "End of PTE"

if [ ! -d "tmp/gcc" ]; then
export CFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT"
mkdir -p tmp/gcc
cd tmp/gcc
../../gcc/configure --target=$TARGET --prefix=$PREFIX --with-newlib --with-isl --disable-multilib --without-libatomic --enable-languages=c --disable-nls --disable-shared --disable-libssp --enable-threads=posix --disable-libgomp --enable-tls --enable-lto --disable-symver && make $NJOBS && make install &> ~/gcc.out && echo "success"
cd -
fi
#read -p "End of GCC"

# workaroud, compiler needs libgomp.spec to support OpenMP
install -m 644 hermit/usr/libomp/libgomp.spec $PREFIX/$TARGET/lib

if [ ! -d "tmp/final" ]; then
export CFLAGS_FOR_TARGET="-m64 -O3 -ftree-vectorize $ARCH_OPT -target x86_64-hermit"
mkdir -p tmp/final
cd tmp/final
cmake -DHERMIT_PREFIX=$PREFIX -DMTUNE=native ../../hermit
make $NJOBS
make install 
cd -
fi
#read -p "End of Final"

cd ..

# Gold: bfd
cd build/binutils/bfd && ./configure && make $NJOBS && cd -

# Gold: libiberty
cd build/binutils/libiberty && ./configure && make $NJOBS && cd -

# Gold
cd build/binutils/gold && ./configure && make $NJOBS && cd -
