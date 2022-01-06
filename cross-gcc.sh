#!/bin/bash
# Copyright 2021-2022 Greg Crist <gmcrist@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source shell-toolkit 2>/dev/null || { echo "shell-toolkit is required"; exit 1; }

function usage() {
    self=$(basename $0)
    echo "Usage: ${self} [options]"
    echo ""
    echo "Options:"
    echo "    --clean                Removes temporary files in the build directory before building"
    echo "    --clean-all            Removes all temporary files (including downloads) in the build directory before building"
    echo "    --binutils <version>   Specifies the version of binutils to build"
    echo "    --gcc <version>        Specifies the version of gcc to build"
    echo "    --build-dir <path>     Specifies the path to the temporary build location"
    echo "    --prefix <path>        Specifies the path where cross gcc will be installed"
    echo "    --target <target>      Specifies the target architecture and os"
    echo ""
}

function main() {
    temp=$(getopt --long help,clean,build-dir:,target:prefix:,binutils:,gcc: -n cross-gcc-build -- "$@")

    config_binutils_ver="2.37"
    config_gcc_ver="9.4.0"

    config_build_dir="$(dirname $(realpath $0))/build"
    config_prefix="${config_build_dir}/toolchain"
    config_target=$(gcc -dumpmachine)
    config_clean=0

    while true; do
        case "$1" in
            --help)
                usage
                return
                ;;

            --clean)
                config_clean=1
                shift
                ;;

            --clean-all)
                config_clean=2
                shift
                ;;

            --build-dir)
                config_build_dir="$2"
                config_prefix="${config_build_dir}/toolchain"
                shift 2
                ;;

            --prefix)
                config_prefix="$2"
                shift 2
                ;;

            --target)
                config_target="$2"
                shift 2
                ;;

            --binutils)
                config_binutils_ver="$2"
                shift 2
                ;;

            --gcc)
                config_gcc_ver="$2"
                shift 2
                ;;

            -- )
                shift
                break
                ;;

            *)
                break
                ;;
        esac
    done

    build_src="${config_build_dir}/src"
    build_log="${config_build_dir}/build.log"

    export PREFIX="${config_prefix}"
    export TARGET="${config_target}"

    echo "Cross GCC build configuration:"
    echo "  build log:  ${build_log}"
    echo "  prefix:     ${PREFIX}"
    echo "  target:     ${TARGET}"
    echo "  gcc:        ${config_gcc_ver}"
    echo "  binutils:   ${config_binutils_ver}"
    echo ""

    _log_config[timestamp]=1
    _log_config[labels.info]="[INFO] "
    _log_config[labels.error]="${colors[red]}[ERROR]${colors[none]} "

    gcc_ver=${config_gcc_ver}
    binutils_ver=${config_binutils_ver}

    binutils_archive="binutils-${binutils_ver}.tar.xz"
    gcc_archive="gcc-${gcc_ver}.tar.xz"

    binutils_url="https://ftp.gnu.org/gnu/binutils/${binutils_archive}"
    gcc_url="ftp://ftp.gnu.org/gnu/gcc/gcc-${gcc_ver}/${gcc_archive}"

    binutils_src="binutils-${binutils_ver}"
    gcc_src="gcc-${gcc_ver}"

    binutils_build="build-binutils"
    gcc_build="build-gcc"

    if [ ! -d ${PREFIX} ]; then
        mkdir -p ${PREFIX}
    fi

    if [ ! -d ${build_src} ]; then
       mkdir -p ${build_src}
    fi

    cd ${build_src}
    if [ ${config_clean} -ne 0 ]; then
        log_info "Cleaning sources..."
        rm -rf "${binutils_src}"
        rm -rf "${binutils_build}"

        rm -rf "${gcc_src}"
        rm -rf "${gcc_build}"

        # Also remove downloaded files
        if [ ${config_clean} -gt 1 ]; then
            rm -rf "${binutils_archive}"
            rm -rf "${gcc_archive}"
        fi
    fi

    if [ ! -f ${binutils_archive} ]; then
        msg="Download binutils (${binutils_archive})"
        log_info ${msg}
        output=$(download ${binutils_url} ${binutils_archive})
        log_passfail $? $msg || { echo ${output} >> ${build_log}; return 1; }
    fi

    if [ ! -f ${gcc_archive} ]; then
        msg="Download gcc (${gcc_archive})"
        log_info ${msg}
        output=$(download ${gcc_url} ${gcc_archive})
        log_passfail $? ${msg} || { echo ${output} >> ${build_log}; return 1; }
    fi

    if [ ! -f ${binutils_archive} ]; then
        log_error "Can't find binutils archive"
        return 1
    fi

    if [ ! -f ${gcc_archive} ]; then
        log_error "Can't find gcc archive"
        return 1
    fi

    if [ -d "${binutils_build}" ]; then
        rm -rf ${binutils_build}
    fi

    log_info "Decompressing binutils archive"
    xz -d -T $(nproc) -c ${binutils_archive} | tar -x >>${build_log} 2>&1
    log_passfail $? "decompress binutils archive" || { return 1; }


    if [ -d "${gcc_build}" ]; then
        rm -rf gcc-${gcc_build}
    fi

    log_info "Decompressing gcc archive"
    xz -d -T $(nproc) -c ${gcc_archive} | tar -x >>${build_log} 2>&1
    log_passfail $? "decompress gcc archive" || { return 1; }

    cd ${build_src}
    mkdir ${binutils_build}
    cd ${binutils_build}

    log_info "Configuring binutils for ${TARGET}..."
    ../${binutils_src}/configure --target=$TARGET --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror >>${build_log} 2>&1
    log_passfail $? "configure binutils" || { return 1; }

    log_info "Building binutils..."
    make -j $(nproc) >>${build_log} 2>&1
    log_passfail $? "build binutils" || { return 1; }

    log_info "Installing binutils"
    make install >>${build_log} 2>&1
    log_passfail $? "install binutils" || { return 1; }

    cd ${build_src}
    mkdir ${gcc_build}
    cd ${gcc_build}

    log_info "Configuring gcc for ${TARGET}..."
    ../${gcc_src}/configure --target=$TARGET --prefix="$PREFIX" --disable-nls --enable-languages=c,c++ --without-headers >>${build_log} 2>&1
    log_passfail $? "configure gcc" || { return 1; }

    log_info "Building gcc..."
    make -j $(nproc) all-gcc >>${build_log} 2>&1
    log_passfail $? "build gcc" || { return 1; }

    log_info "Building libgcc..."
    make -j $(nproc) all-target-libgcc >>${build_log} 2>&1
    log_passfail $? "build libgcc" || { return 1; }

    log_info "Installing gcc..."
    make install-gcc >>${build_log} 2>&1
    log_passfail $? "install gcc" || { return 1; }

    log_info "Installing libgcc..."
    make install-target-libgcc >>${build_log} 2>&1
    log_passfail $? "install libgcc" || { return 1; }
}

main $@
exit $?
