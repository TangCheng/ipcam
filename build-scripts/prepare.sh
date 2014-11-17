#!/bin/sh

BUILD_HOME=$(pushd `dirname %0` > /dev/null 2>&1; pwd; popd > /dev/null 2>&1)
SOURCE_HOME=${BUILD_HOME}/sources

url_base="https://github.com/TangCheng"
pkg_list=(\
	"ipcam_thirdparties:zlib-1.2.8" \
	"ipcam_thirdparties:http-parser-2.3" \
	"ipcam_thirdparties:zeromq-4.0.4" \
	"ipcam_thirdparties:czmq-2.2.0" \
	"ipcam_thirdparties:pcre-8.36" \
	"ipcam_thirdparties:lighttpd-1.4.35" \
	"ipcam_thirdparties:gettext-0.16.1" \
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
	"ionvif" \
	"imedia_rtsp" \
	"hi3518-apps")

pushd ${BUILD_HOME} > /dev/null

if [ ! -d ${SOURCE_HOME} ]; then
  mkdir -p ${SOURCE_HOME}
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

