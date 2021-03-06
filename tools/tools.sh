#!/usr/bin/env bash

export LC_ALL="C"

BASE_DIR=$PWD

TARBALL_DIR=$BASE_DIR/tarballs
BUILD_DIR=$BASE_DIR/build
TARGET_DIR=$BASE_DIR/target
PATCH_DIR=$BASE_DIR/patches
SDK_DIR=$TARGET_DIR/SDK

if [ -z "$USESYSTEMCOMPILER" ]; then
  export CC=clang
  export CXX=clang++
elif [ -n "$CC" -o -n "$CXX" ]; then
  echo "CC/CXX should not be set, continuing in 5 seconds..." 1>&2
  sleep 5
fi

# enable debug messages
test -n "$OCDEBUG" && set -x

PLATFORM="`uname -s`"
SCRIPT="`basename $0`"

if [[ $SCRIPT != *wrapper/build.sh ]]; then
  # how many concurrent jobs should be used for compiling?
  JOBS=${JOBS:=`tools/get_cpu_count.sh`}

  if [ $SCRIPT != "build.sh" -a $SCRIPT != "build_clang.sh" -a \
       $SCRIPT != "mount_xcode_image.sh" -a \
       $SCRIPT != "gen_sdk_package_darling_dmg.sh" -a \
       $SCRIPT != "gen_sdk_package_p7zip.sh" ]; then
    `tools/osxcross_conf.sh`

    if [ $? -ne 0 ]; then
      echo -n "you need to complete ./build.sh first, before you can start "
      echo "building $DESC"
      exit 1
    fi
  fi
fi

function require()
{
  set +e
  which $1 &>/dev/null
  while [ $? -ne 0 ]
  do
    echo ""
    read -p "Please install $1 then press enter"
    which $1 &>/dev/null
  done
  set -e
}

if [[ $PLATFORM == *BSD ]]; then
  MAKE=gmake
else
  MAKE=make
fi

require $MAKE

function extract()
{
  test $# -ge 2 -a $# -lt 4 && test $2 -eq 2 && echo ""
  echo "extracting `basename $1` ..."

  local tarflags

  tarflags="xf"
  test -n "$OCDEBUG" && tarflags+="v"

  case $1 in
    *.pkg)
      which xar &>/dev/null || exit 1
      xar -xf $1
      cat Payload | gunzip -dc | cpio -i 2>/dev/null && rm Payload
      ;;
    *.tar.xz)
      xz -dc $1 | tar $tarflags -
      ;;
    *.tar.gz)
      gunzip -dc $1 | tar $tarflags -
      ;;
    *.tar.bz2)
      bzip2 -dc $1 | tar $tarflags -
      ;;
    *)
      echo "Unhandled archive type"
      exit 1
      ;;
  esac

  if [ $# -eq 2 -o $# -eq 4 ]; then
    echo ""
  fi
}

function verbose_cmd()
{
  echo "$@"
  eval "$@"
}

function check_cxx_stdlib()
{
  set +e

  $CXX $CXXFLAGS -std=c++0x $BASE_DIR/tools/stdlib-test.cpp -S -o- \
    2>$BUILD_DIR/stdlib-test.log 1>/dev/null
  echo "$?"

  set -e
}

function test_compiler()
{
  echo -ne "testing $1 ... "
  $1 $2 -O2 -Wall -o test
  rm test
  echo "works"
}

function test_compiler_cxx11()
{
  set +e
  echo -ne "testing $1 -stdlib=libc++ -std=c++11 ... "
  $1 $2 -O2 -stdlib=libc++ -std=c++11 -Wall -o test &>/dev/null
  if [ $? -eq 0 ]; then
    rm test
    echo "works"
  else
    echo "failed (ignored)"
  fi
  set -e
}

# exit on error
set -e
