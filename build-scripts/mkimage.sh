#!/bin/sh

me=$(basename $0)

usage="\
Usage: $0 [-h|-t]
OPTIONS:
  -h, --help               print this help, then exit
  -t  --toolchain=TOOLCHAIN
                           choose the toolchain [default=v100]
"

help="
Try \`$me --help' for more information."

BUILD_HOME=${PWD}
SOURCE_HOME=${BUILD_HOME}/sources
IPCAM_THIRDPARTIES="${SOURCE_HOME}/ipcam_thirdparties"
user=$(whoami)

tc=v100

# Parse command line
while [ $# -gt 0 ]; do
  case $1 in
    --help | -h)
      echo "$usage" ; exit ;;
    -t)
      shift ; tc=$1 ; shift ;;
    --toolchain=*)
      tc=$(expr "X$1" : '[^=]*=\(.*\)') ; shift ;;
    -*)
      echo "$me: invalid option $1${help}" >&2
      exit 1 ;;
    *) # Stop option processing
      break ;;
  esac
done

case ${tc} in
  v100)
    if ! which arm-hisiv100nptl-linux-gcc > /dev/null 2>&1; then
      PATH=${PATH}:/opt/hisi-linux-nptl/arm-hisiv100-linux/target/bin
      CROSS_COMPILE=arm-hisiv100nptl-linux-
    fi
    ;;
  v200)
    if ! which arm-hisiv200-linux-gcc > /dev/null 2>&1; then
      PATH=${PATH}:/opt/hisi-linux/x86-arm/arm-hisiv200-linux/target/bin
      CROSS_COMPILE=arm-hisiv200-linux-
    fi
    ;;
  *)
    echo "$me: invalid toolchain ${tc}${help}"
    exit 1
    ;;
esac
export PATH CROSS_COMPILE

if [ x"$user" = "xroot" ]; then
  echo "Must not be root to run this script" >&2
  exit 1
fi

if ! [ -d rootfs_uclibc ]; then
  echo "rootfs_uclibc directory not found, please build first." >&2
  exit 1
fi

rm -rf staging
cp -af rootfs_uclibc/apps staging
cp -af rootfs_uclibc/bin staging
cp -af rootfs_uclibc/etc staging
cp -af rootfs_uclibc/ko staging
cp -af rootfs_uclibc/usr staging


function strip_dirs() {
  if [ $# -le 0 ]; then
    echo "invalid argument"
    return
  fi

  pushd $1
  for f in $(find -type f); do
    if file $f | grep "not stripped" >/dev/null 2>&1; then
      chmod u+w $f
      ${CROSS_COMPILE}strip -s $f
    fi
  done
  popd
}

pushd staging
  pushd usr
    rm -rf include doc share/*
    pushd bin
    ls | grep -v timer \
       | grep -v sqlite3 \
       | grep -v *gdbserver \
       | xargs rm -f
    popd
    find -name "*.la" -exec rm -f "{}" \;
    find -name "*.a" -exec rm -f "{}" \;
    rm -rf lib/pkgconfig
    rm -rf lib/libffi-3.0.13/
    rm -rf lib/glib-2.0/
    rm -rf lib/gettext
    rm -rf lib/gio
    rm -f  lib/libgettext*
    strip_dirs .
    cp -af ${IPCAM_THIRDPARTIES}/fonts share/
#    cp -af /usr/share/zoneinfo share/
#    mv share/zoneinfo/Asia/{Shanghai,Beijing}
  popd
  for dir in iconfig iajax isystem imedia_rtsp ionvif ionvif-discovery bin; do
    strip_dirs $dir
  done
  rm -rf include
  rm -rf lib
  rm -rf share
popd


mkdir -p images
## squashfs
rm -f images/rootfs_64k.squashfs
mksquashfs staging/* images/rootfs_64k.squashfs -b 64k -comp xz -no-xattrs
## jffs2
rm -f images/rootfs_64k.jffs2
mkfs.jffs2 -d staging/ -l -e 0x10000 -o images/rootfs_64k.jffs2

