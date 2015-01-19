#!/bin/sh

me=$(basename $0)

usage="\
Usage: $0 [OPTIONS]
OPTIONS:
  -h, --help               print this help, then exit
      --with-hisisdk=DIR   specify the hisi sdk path
"

help="
Try \`$me --help' for more information."

# Parse command line
while [ $# -gt 0 ]; do
  case $1 in
    --help | -h)
      echo "$usage" ; exit ;;
    --with-hisisdk=*)
      hisi_sdk=$(expr "X$1" : '[^=]*=\(.*\)') ; shift ;;
    *)
      echo "$me: invalid parameter $1${help}" >&2
      exit 1 ;;
  esac
done

HISI_SDK_DIR="Hi3518_SDK_V1.0.9.0"
HISI_SDK_TARBALL="Hi3518_SDK_V1.0.9.0.tgz"
BUILD_HOME=$(pushd `dirname %0` > /dev/null 2>&1; pwd; popd > /dev/null 2>&1)
SOURCE_HOME=${BUILD_HOME}/sources

url_base="https://github.com/TangCheng"
pkg_list=(\
	"ipcam_thirdparties:gdb-7.8.1" \
	"ipcam_thirdparties:zlib-1.2.8" \
	"ipcam_thirdparties:http-parser-2.3" \
	"ipcam_thirdparties:zeromq-4.0.4" \
	"ipcam_thirdparties:czmq-2.2.0" \
	"ipcam_thirdparties:pcre-8.36" \
	"ipcam_thirdparties:lighttpd-1.4.35" \
	"ipcam_thirdparties:gettext-0.18.3.2" \
	"ipcam_thirdparties:libffi-3.0.13" \
	"ipcam_thirdparties:glib-2.40.0" \
	"ipcam_thirdparties:json-glib-1.0.0" \
	"ipcam_thirdparties:libpng-1.2.50" \
	"ipcam_thirdparties:freetype-2.5.3" \
	"ipcam_thirdparties:SDL2-2.0.1" \
	"ipcam_thirdparties:SDL2_ttf-2.0.12" \
	"ipcam_thirdparties:yaml-0.1.5" \
	"ipcam_thirdparties:sqlite-3.8.4.3" \
	"ipcam_thirdparties:gom" \
	"ipcam_thirdparties:live" \
	"ipcam_thirdparties:fcgi-2.4.1" \
	"upload" \
	"libipcam_base" \
	"iconfig" \
	"isystem" \
	"iajax" \
	"itrain" \
	"ionvif" \
	"imedia_rtsp" \
	"hi3518-apps")

pushd ${BUILD_HOME} > /dev/null

if [ ! -d ${SOURCE_HOME} ]; then
  mkdir -p ${SOURCE_HOME}
fi

if [ ! -d ${SOURCE_HOME}/${HISI_SDK_DIR} ]; then
  if [ "x${hisi_sdk}" = "x" ]; then
    hisi_sdk=${BUILD_HOME}/${HISI_SDK_TARBALL}
  fi
  if [ -f ${hisi_sdk} ]; then
    tar -zvxf ${hisi_sdk} -C ${SOURCE_HOME} || exit 1
    pushd ${SOURCE_HOME}/${HISI_SDK_DIR} > /dev/null
      ./sdk.unpack
    popd > /dev/null
  else
    echo "HISI SDK not found." >&2
    echo "Try to run:"
    echo "$0 --with-hisisdk=/path/to/Hi3518_SDK_V1.0.9.0.tgz" >&2
    exit 1
  fi
fi

for pkg in ${pkg_list[@]}; do
  saved_IFS="${IFS}"
  IFS=":" arr=($pkg)
  IFS=${saved_IFS}
  pkg_url="${url_base}/${arr[0]}.git"
  pkg_dir=${arr[0]}
  pkg_subdir=${arr[1]}

  echo "${pkg_url} => ${pkg_dir}"
  if [ -d "sources/${pkg_dir}" ]; then
    pushd "sources/${pkg_dir}" > /dev/null
      git pull
    popd > /dev/null
  else
    pushd sources > /dev/null
      git clone ${pkg_url}
    popd > /dev/null
  fi

  if [ "x${pkg_subdir}" != "x" ]; then
    ln -sf ${SOURCE_HOME}/${pkg_dir}/${pkg_subdir} ${SOURCE_HOME}/
  fi
done

popd > /dev/null

