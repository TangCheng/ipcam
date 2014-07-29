#!/bin/sh

me=$(basename $0)

usage="\
Usage: $0 [-h] [-a] [-c] [-f] [-t v100|v200] [PACKAGE[PREFIX[CONF_OPT]]]
  -h, --help               print this help, then exit
  -A, --autoreconf         force run ./autogen.sh and autoreconf
  -C, --clean              make clean
  -D, --distclean          make distclean
  -c, --configure          force run configure
  -f, --force              force to rebuild
  -i, --install            force to install
  -t v100|v200             choose the toolchain [default=v100]
  -v, --verbose            verbose output
"

help="
Try \`$me --help' for more information."

force_ac=no
force_conf=no
force_build=no
force_install=no
make_clean=no
make_distclean=no
verbose=no
tc=v100

# Parse command line
while [ $# -gt 0 ]; do
  case $1 in
    --help | -h)
      echo "$usage" ; exit ;;
    -A | --autoreconf)
      force_ac=yes ; shift ;;
    -C | --clean)
      make_clean=yes ; shift ;;
    -D | --distclean)
      make_distclean=yes ; shift ;;
    -c | --configure)
      force_conf=yes ; shift ;;
    -f | --force)
      force_build=yes ; shift ;;
    -i | --install)
      force_install=yes ; shift ;;
    -t)
      shift ; tc=$1 ; shift ;;
    -v | --verbose)
      verbose=yes ; shift ;;
    -*)
      echo "$me: invalid option $1${help}" >&2
      exit 1 ;;
    *) # Stop option processing
      break ;;
  esac
done

BUILD=${MACHTYPE}
case ${tc} in
  v100)
    if ! which arm-hisiv100nptl-linux-gcc > /dev/null 2>&1; then
      PATH=${PATH}:/opt/hisi-linux-nptl/arm-hisiv100-linux/target/bin
    fi
    TARGET=arm-hisiv100nptl-linux
    TARGET_ROOTFS=rootfs_uclibc
    ;;
  v200)
    if ! which arm-hisiv200-linux-gcc > /dev/null 2>&1; then
      PATH=${PATH}:/opt/hisi-linux/x86-arm/arm-hisiv200-linux/target/bin
    fi
    TARGET=arm-hisiv200-linux
    TARGET_ROOTFS=rootfs_glibc
    ;;
  *)
    echo "$me: invalid toolchain ${tc}${help}"
    exit 1 ;;
esac
export PATH

if [ "x${NR_CPUS}" = "x" ]; then
  NR_CPUS=$(expr $(cat /proc/cpuinfo | grep 'processor' | wc -l) \* 2)
fi
export NR_CPUS

DEF_CONF_OPTS=" --build=${BUILD} --host=${TARGET} "
PREFIX=/usr

CROSS_COMPILE=${TARGET}-

PREFIX=/usr
BUILD_HOME=${PWD}
BUILD_LOG=${BUILD_HOME}/build.log
SOURCE_HOME=${BUILD_HOME}/sources
BUILD_TMP=${BUILD_HOME}/tmp
SYSROOT=${BUILD_HOME}/rootfs_uclibc
DESTDIR=${SYSROOT}

PKG_CONFIG_PATH=${SYSROOT}/usr/lib/pkgconfig
PKG_CONFIG_SYSROOT_DIR=${SYSROOT}

export DESTDIR
export PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR

CPPFLAGS="-I${SYSROOT}/usr/include"
LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib -lstdc++"
#LDFLAGS+="-Wl,-rpath-link -Wl,${SYSROOT}/usr/lib "\
#         "-Wl,-rpath -Wl,/lib -Wl,-rpath -Wl,/usr/lib"
export CPPFLAGS LDFLAGS

## Prepare the build environment
rm -f ${BUILD_LOG}
if ! [ -d ${SYSROOT} ]; then
  if [ -f ${TARGET_ROOTFS}.tgz ]; then
    tar -zvxf ${TARGET_ROOTFS}.tgz
  else
    warn "Initial rootfs not found."
  fi
  force_build=yes
fi

function __fatal() {
  echo
  echo "FATAL: $*"
  echo "See config.log for detail."
  echo
}

function __warn() {
  echo
  echo "WARN: $*"
  echo
}

function __display_banner() {
  echo
  echo "*********************************************************************"
  echo "* Building $1"
  echo "*********************************************************************"
  echo
}

function fatal() {
  __fatal $* | tee -a ${BUILD_LOG} >&2
  exit 1
}

function warn() {
  __warn $* | tee -a ${BUILD_LOG} >&2
}

function display_banner() {
  __display_banner $* | tee -a ${BUILD_LOG}
}

function patch_lt_objects() {
  if [ $# -lt 2 ]; then
    return;
  fi
  local prefix=$1
  shift
  pushd ${SYSROOT}${prefix}/lib > /dev/null
    local lt_objs=$(ls $*)
    local opts=" -e s;libdir='${prefix};libdir='${SYSROOT}${prefix};"
    local lt_obj=
    for lt_obj in ${lt_objs}; do
      local fn=$(basename ${lt_obj})
      opts+=" -e ""s;${prefix}/lib/${fn};${SYSROOT}${prefix}/lib/${fn};"
    done
    sed -i ${opts} ${lt_objs}
  popd > /dev/null
}


#
# function: build_ac_package package_name package_path prefix
# parameters:
#   $1           package name
#   $2           package path
#   $3           prefix       [default=/usr]
#   $4           optional config options
#
function build_ac_package() {
  local f_ac=${force_ac}
  local f_conf=${force_conf}
  local f_build=${force_build}
  local f_inst=${force_install}

  ## Parse options
  while [ $# -gt 0 ]; do
    case $1 in
      -f)
        f_build=yes ; shift ;;
      -A)
        f_ac=yes ; shift ;;
      -c)
        f_conf=yes ; shift ;;
      -i)
        f_build=yes ; shift ;;
      *)  ## Stop option processing
        break ;;
    esac
  done

  if [ $# -lt 2 ]; then
    fatal 'Usage build_ac_package NAME PATH [PREFIX] [CONF_OPTS]' >&2
  fi

  local ltobjs=""

  local pkg_name=$1; shift
  local pkg_path=$1; shift
  local prefix=/usr

  if [ $# -gt 0 ]; then
    prefix=$1;   shift
  fi

  if ! [ -d ${SOURCE_HOME}/${pkg_path} ]; then
    fatal "Package ${pkg_name} not found"
  fi

  display_banner "$pkg_name at ${SOURCE_HOME}/${pkg_path}"

  ## check if package has already been built succesful
  if [ -f ${BUILD_TMP}/${pkg_path}-built-ok \
       -a "x${f_build}" != "xyes" \
       -a "x${f_inst}" != "xyes" \
     ];
  then
    return
  fi

  ## make distclean
  if [ "x${make_distclean}" = "xyes" ]; then
    if [ -f ${SOURCE_HOME}/${pkg_path}/Makefile ]; then
      make distclean -C ${SOURCE_HOME}/${pkg_path} >>${BUILD_LOG} 2>&1
    fi
    rm -f ${BUILD_TMP}/${pkg_path}-built-ok
    return
  fi

  ## make clean
  if [ "x${make_clean}" = "xyes" ]; then
    if [ -f ${SOURCE_HOME}/${pkg_path}/Makefile ]; then
      make clean -C ${SOURCE_HOME}/${pkg_path} >>${BUILD_LOG} 2>&1
    fi
    rm -f ${BUILD_TMP}/${pkg_path}-built-ok
    return
  fi

  pushd ${SOURCE_HOME}/${pkg_path} > /dev/null
    ## run ./autogen.sh and autoreconf
    if [ "x${f_ac}" = "xyes" ]; then
      if [ -f autogen.sh ]; then
        ./autogen.sh -h >>${BUILD_LOG} 2>&1
      fi
      autoreconf >>${BUILD_LOG} 2>&1
    fi
    ## configure
    if ! [ -f Makefile -a "x${f_conf}" != "xyes" ]; then
      ./configure --prefix=${prefix} \
          ${DEF_CONF_OPTS} $* >>${BUILD_LOG} 2>&1 \
          || fatal "error building $pkg_name"
    fi
    ## build and install
    make -j${NR_CPUS} >>${BUILD_LOG} 2>&1 || fatal "error building ${pkg_name}"
    ## install to tmp directory to find .la files
    make install DESTDIR=${BUILD_TMP} >>${BUILD_LOG} 2>&1 \
      || fatal "error building ${pkg_name}"
    if [ -d ${BUILD_TMP}${prefix}/lib ]; then
      pushd ${BUILD_TMP}${prefix}/lib > /dev/null
        ltobjs=$(find -name "lib*.la" | sed 's;\./;;')
        find -name "lib*.la" -delete
      popd > /dev/null
    fi
    make install DESTDIR=${SYSROOT} >>${BUILD_LOG} 2>&1 \
      || fatal "error building ${pkg_name}"
    ## patch all libtool .la files
    if [ "x${ltobjs}" != "x" ]; then
      patch_lt_objects ${prefix} ${ltobjs}
    fi
    ## Succeed, mark this package
    touch ${BUILD_TMP}/${pkg_path}-built-ok
  popd > /dev/null
}

## Build listed-packages
if [ $# -gt 0 ]; then
  pkg=$1 ; shift
  build_ac_package ${pkg} ${pkg} $*
  exit 0
fi


pushd sources/zlib-1.2.8
  display_banner ZLIB
  if ! [ -L libz.so ]; then
    CC=${CROSS_COMPILE}gcc \
    ./configure --prefix=/usr || exit 1;
    CC=${CROSS_COMPILE}gcc make -j${NR_CPUS} || exit 1;
  fi
  CC=${CROSS_COMPILE}gcc make install || exit 1;
popd


pushd sources/http-parser-2.3
  display_banner HTTP-PARSER
  CC=${CROSS_COMPILE}gcc \
  AR=${CROSS_COMPILE}ar \
  make library
  cp libhttp_parser.so.2.3 ${SYSROOT}/usr/lib
  pushd ${SYSROOT}/usr/lib
    ln -sf libhttp_parser.so.2.3 libhttp_parser.so
  popd
  mkdir -p ${SYSROOT}/usr/include
  cp -v http_parser.h ${SYSROOT}/usr/include
popd


build_ac_package ZeroMQ zeromq-4.0.4 ${PREFIX} \
    --without-documentation \
    --enable-shared --disable-static


build_ac_package CZMQ czmq-2.2.0 ${PREFIX} \
    --enable-shared --disable-static


build_ac_package LIGHTTPD lighttpd-1.4.35 ${PREFIX} \
    --enable-shared --disable-static \
    --without-zlib --without-bzip2 \
    --enable-lfs --disable-ipv6 \
    --without-pcre --disable-mmap


build_ac_package GETTEXT gettext-0.18.3.2 ${PREFIX} \
    --enable-shared --disable-static \
    --disable-openmp --disable-acl \
    --disable-curses \
    --without-emacs --without-git --without-cvs \
    --without-bzip2 --without-xz


build_ac_package libFFI libffi-3.0.13 ${PREFIX} \
    --enable-shared --disable-static


build_ac_package GLIB glib-2.40.0 ${PREFIX} \
    --enable-shared --disable-static \
    --with-libiconv=no --disable-selinux \
    --disable-gtk-doc --disable-gtk-doc-html --disable-gtk-doc-pdf \
    --disable-man \
    --disable-xattr \
    --disable-dtrace --disable-systemtap \
    glib_cv_stack_grows=no glib_cv_uscore=yes \
    ac_cv_func_posix_getpwuid_r=yes ac_cv_func_posix_getgrgid_r=yes


build_ac_package JSON-GLIB json-glib-1.0.0 ${PREFIX} \
    --enable-shared --disable-static \
    --disable-gtk-doc --disable-gtk-doc-html --disable-gtk-doc-pdf \
    --disable-man \
    --disable-glibtest \
    --disable-introspection \
    --disable-nls


#build_ac_package HARFBUZZ harfbuzz-0.9.33 ${PREFIX} \
#    --enable-shared --disable-static \
#    --disable-gtk-doc --disable-gtk-doc-html \
#    --disable-introspection \
#    --without-cairo --without-freetype \
#    --without-icu


build_ac_package LIBPNG libpng-1.2.50 ${PREFIX} \
    --enable-shared --disable-static


build_ac_package -c FreeType freetype-2.5.3 ${PREFIX} \
    --enable-shared --disable-static \
    --with-zlib --without-bzip2 \
    --with-png --with-harfbuzz=no \
    --without-old-mac-fonts --without-fsspec --without-fsref \
    --without-quickdraw-toolbox --without-quickdraw-carbon \
    --without-ats
sed -i -e "s;includedir=\"${PREFIX};includedir=\"${SYSROOT}${PREFIX};" \
    -e "s;libdir=\"${PREFIX};libdir=\"${SYSROOT}${PREFIX};" \
    ${SYSROOT}${PREFIX}/bin/freetype-config


build_ac_package SDL2 SDL2-2.0.1 ${PREFIX} \
    --disable-audio --disable-video --disable-render \
    --disable-event --disable-joystick \
    --disable-haptic --disable-power \
    --disable-filesystem --enable-threads \
    --disable-file --disable-loadso --disable-cpuinfo \
    --disable-assembly --disable-ssemath \
    --disable-mmx --disable-3dnow --disable-sse --disable-sse2 \
    --disable-oss --disable-alsa --disable-alsatest \
    --disable-esd --disable-pulseaudio \
    --disable-arts  --disable-nas --disable-sndio --disable-diskaudio \
    --disable-dummyaudio --disable-video-x11 \
    --disable-directfb --disable-fusionsound \
    --disable-libudev --disable-dbus \
    --disable-input-tslib --enable-pthread \
    --disable-directx --enable-sdl-dlopen \
    --disable-clock_gettime --enable-rpath \
    --disable-render-d3d


build_ac_package SDL2_ttf SDL2_ttf-2.0.12 ${PREFIX} \
    --enable-shared --disable-static \
    --disable-sdltest --without-x \
    --with-sdl-prefix=${SYSROOT}${PREFIX} \
    --with-freetype-prefix=${SYSROOT}${PREFIX}


build_ac_package YAML yaml-0.1.5 ${PREFIX} \
    --enable-shared --disable-static


build_ac_package SQLITE sqlite-3.8.4.3 ${PREFIX} \
    --enable-shared --disable-static


LDFLAGS="${LDFLAGS} -lintl" \
build_ac_package GOM gom ${PREFIX} \
    --enable-shared --disable-static \
    --disable-glibtest \
    --disable-nls \
    --disable-gtk-doc --disable-gtk-doc-html --disable-gtk-doc-pdf \
    --disable-introspection


# Build live555
pushd ${SOURCE_HOME}/live >/dev/null
  display_banner "LIVE555"
  ./genMakefiles armlinux-with-shared-libraries >>${BUILD_LOG} 2>&1 \
    || fatal "error building live555."
  make -j${NR_CPUS} >>${BUILD_LOG} 2>&1 || fatal "error building live555"
  if [ -f ${SYSROOT}${PREFIX}/lib/libliveMedia* ]; then
    rm -f ${SYSROOT}${PREFIX}/lib/libliveMedia*
  fi
  if [ -f ${SYSROOT}${PREFIX}/lib/libgroupsock* ]; then
    rm -f ${SYSROOT}${PREFIX}/lib/libgroupsock*
  fi
  if [ -f ${SYSROOT}${PREFIX}/lib/libUsageEnvironment* ]; then
    rm -f ${SYSROOT}${PREFIX}/lib/libUsageEnvironment*
  fi
  if [ -f ${SYSROOT}${PREFIX}/lib/libBasicUsageEnvironment* ]; then
    rm -f ${SYSROOT}${PREFIX}/lib/libBasicUsageEnvironment*
  fi
  make install DESTDIR=${DESTDIR} >>${BUILD_LOG} 2>&1 \
    || fatal "error building live555."
popd >/dev/null


build_ac_package LIBIPCAM_BASE libipcam_base ${PREFIX} \
    --enable-shared --disable-static


build_ac_package ICONFIG iconfig /opt \
    --sysconfdir=/etc


NR_CPUS=1 \
build_ac_package IONVIF ionvif /opt \
    --enable-shared --disable-static \
    --disable-ipv6 \
    --disable-ssl --disable-gnutls \
    --disable-samples \
    ac_cv_func_malloc_0_nonnull=yes

build_ac_package IMEDIA imedia /opt \
    --enable-hi3518 --disable-hi3516

CPPFLAGS="-I/rootfs/usr/include/liveMedia \
          -I/rootfs/usr/include/groupsock \
          -I/rootfs/usr/include/BasicUsageEnvironment \
          -I/rootfs/usr/include/UsageEnvironment" \
build_ac_package IRTSP irtsp /opt

echo
echo "Build completely successful."
echo
