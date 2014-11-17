#!/bin/sh

IPCAM_THIRDPARTIES="${HOME}/devel/ipcam/ipcam_thirdparties"
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
cp -af rootfs_uclibc/apps staging
cp -af rootfs_uclibc/bin staging
cp -af rootfs_uclibc/etc staging
cp -af rootfs_uclibc/ko staging
cp -af rootfs_uclibc/usr staging

CROSS_COMPILE=arm-hisiv100nptl-linux-

function strip_dirs() {
  if [ $# -le 0 ]; then
    echo "invalid argument"
    return
  fi

  pushd $1
  for f in $(find -type f); do
    if file $f | grep "not stripped" >/dev/null 2>&1; then
      ${CROSS_COMPILE}strip -s $f
    fi
  done
  popd
}

pushd staging
  pushd usr
    rm -rf include doc share/*
    pushd bin
    ls | grep -v timer | grep -v sqlite3 | xargs rm -f
    popd
    find -name "*.la" -exec rm -f "{}" \;
    find -name "*.a" -exec rm -f "{}" \;
    rm -rf lib/pkgconfig
    rm -rf lib/libffi-3.0.13/
    rm -rf lib/glib-2.0/
    rm -rf lib/gettext
    rm -rf lib/gio
    strip_dirs .
    cp -a ${IPCAM_THIRDPARTIES}/fonts share/
    cp -a /usr/share/zoneinfo share/
    mv share/zoneinfo/Asia/{Shanghai,Beijing}
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

