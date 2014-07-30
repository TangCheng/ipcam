#!/bin/sh

user=$(whoami)

if [ x"$user" = "xroot" ]; then
  echo "Must not be root to run this script" >&2
  exit 1
fi

if ! [ -d rootfs_uclibc ]; then
  echo "rootfs_uclibc directory not found, please build first." >&2
  exit 1
fi

rm -rf staging
cp -af rootfs_uclibc staging

CROSS_COMPILE=arm-hisiv100nptl-linux-

function strip_dirs() {
  if [ $# -le 0 ]; then
    echo "invalid argument"
    return
  fi

  for f in $(find -type f); do
    if file $f | grep "not stripped" >/dev/null 2>&1; then
      ${CROSS_COMPILE}strip -s $f
    fi
  done
}

pushd staging
  pushd usr
    rm -rf include doc share
    strip_dirs .
    rm -f bin/*.gsl
    rm -f bin/*-config
    find -name "*.la" -exec rm -f "{}" \;
    find -name "*.a" -exec rm -f "{}" \;
    rm -rf lib/pkgconfig
    rm -rf lib/libffi-3.0.13/
    rm -rf lib/glib-2.0/
  popd
popd


mkdir -p images
## squashfs
mksquashfs staging/usr/* images/rootfs_64k.squashfs -b 64k -comp xz -no-xattrs
## jffs2
mkfs.jffs2 -d staging/usr/ -l -e 0x10000 -o images/rootfs_64k.jffs2

