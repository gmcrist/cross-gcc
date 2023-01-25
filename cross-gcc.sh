#!/usr/bin/env bash
# Copyright 2021-2023 Greg Crist <gmcrist@gmail.com>
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
    echo "Basic Options:"
    echo "    --build-dir <path>     Specifies the path to the temporary build location"
    echo "    --clean                Removes temporary files in the build directory before building"
    echo "    --clean-all            Removes all temporary files (including downloads) in the build directory before building"
    echo ""
    echo "Target/Install Configuration:"
    echo "    --target <target>      Specifies the target architecture and os"
    echo "    --prefix <path>        Specifies the path where cross gcc will be installed"
    echo ""
    echo "Version Configuration:"
    echo "    --gcc <version>        Specifies the version of gcc to build"
    echo "    --gdb <version>        Specifies the version of gdb to build"
    echo "    --binutils <version>   Specifies the version of binutils to build"
    echo ""
}

function prereq_check() {
    err=0

    for cmd in gcc make python3; do
        which ${cmd} || { log_error "${cmd} not found";  err=1; }
    done

    if [[ "$OSTYPE" == "darwin"* ]]; then
        for cmd in brew; do
            which ${cmd} || { log_error "${cmd} not found";  err=1; }
        done
    fi

    if [ ${err} -ne 0 ]; then
        return 1
    fi

    return 0
}

function cpu_count() {
    cpus=1

    if [[ "$OSTYPE" == "darwin"* ]]; then
        cpus=$(sysctl -n hw.logicalcpu)
    else
        cpus=$(nproc)
    fi

    echo ${cpus}
}

function main() {
    if [ $# -gt 1 ]; then
        temp=$(getopt --long help,build-dir:,clean,clean-all,target:prefix:,gcc:,gdb:,binutils:, -n cross-gcc-build -- "$@")
    fi

    config_gcc_ver="12.1.0"
    config_gdb_ver="12.1"
    config_binutils_ver="2.37"

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

            --gcc)
                config_gcc_ver="$2"
                shift 2
                ;;

            --gdb)
                config_gdb_ver="$2"
                shift 2
                ;;

            --binutils)
                config_binutils_ver="$2"
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

    prereq_check || { log_error "missing pre-requisites"; return 1; }


    # Ensure these are cleared
    unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH INCLUDE LD_LIBRARY_PATH LIBRARY_PATH PKG_CONFIG_PATH

    build_src="${config_build_dir}/src"
    build_log="${config_build_dir}/build.log"

    python_path=$(which python3)

    export PREFIX="${config_prefix}"
    export TARGET="${config_target}"

    echo "Cross GCC build configuration:"
    echo "  build log:  ${build_log}"
    echo "  prefix:     ${PREFIX}"
    echo "  target:     ${TARGET}"
    echo "  gcc:        ${config_gcc_ver}"
    echo "  gdb:        ${config_gdb_ver}"
    echo "  binutils:   ${config_binutils_ver}"
    echo ""

    _log_config[timestamp]=1
    _log_config[labels.info]="[INFO] "
    _log_config[labels.error]="${colors[red]}[ERROR]${colors[none]} "

    gcc_ver=${config_gcc_ver}
    gcc_archive="gcc-${gcc_ver}.tar.xz"
    gcc_url="https://ftp.gnu.org/gnu/gcc/gcc-${gcc_ver}/${gcc_archive}"
    gcc_src="gcc-${gcc_ver}"
    gcc_build="build-gcc"

    gdb_ver=${config_gdb_ver}
    gdb_archive="gdb-${gdb_ver}.tar.xz"
    gdb_url="https://ftp.gnu.org/gnu/gdb/${gdb_archive}"
    gdb_src="gdb-${gdb_ver}"
    gdb_build="build-gdb"

    binutils_ver=${config_binutils_ver}
    binutils_archive="binutils-${binutils_ver}.tar.xz"
    binutils_url="https://ftp.gnu.org/gnu/binutils/${binutils_archive}"
    binutils_src="binutils-${binutils_ver}"
    binutils_build="build-binutils"

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

        rm -rf "${gdb_src}"
        rm -rf "${gdb_build}"

        # Also remove downloaded files
        if [ ${config_clean} -gt 1 ]; then
            rm -rf "${binutils_archive}"
            rm -rf "${gcc_archive}"
            rm -rf "${gdb_archive}"

            rm -rf ${build_dir}
        fi
    fi

    if [ ! -f ${binutils_archive} ]; then
        msg="Download binutils (${binutils_archive})"
        log_info ${msg}
        output=$(download ${binutils_url} ${binutils_archive})
        log_passfail $? $msg || { echo ${output} >> ${build_log}; return 1; }
    fi

    if [ ! -f ${binutils_archive} ]; then
        log_error "Can't find binutils archive"
        return 1
    fi

    if [ ! -f ${gcc_archive} ]; then
        msg="Download gcc (${gcc_archive})"
        log_info ${msg}
        output=$(download ${gcc_url} ${gcc_archive})
        log_passfail $? ${msg} || { echo ${output} >> ${build_log}; return 1; }
    fi

    if [ ! -f ${gcc_archive} ]; then
        log_error "Can't find gcc archive"
        return 1
    fi

    if [ ! -f ${gdb_archive} ]; then
        msg="Download gdb (${gdb_archive})"
        log_info ${msg}
        output=$(download ${gdb_url} ${gdb_archive})
        log_passfail $? ${msg} || { echo ${output} >> ${build_log}; return 1; }
    fi

    if [ ! -f ${gdb_archive} ]; then
        log_error "Can't find gdb archive"
        return 1
    fi


    log_info "Decompressing binutils archive"
    if [ -d "${binutils_build}" ]; then
        rm -rf ${binutils_build}
    fi
    xz -d -T $(cpu_count) -c ${binutils_archive} | tar -x >>${build_log} 2>&1
    log_passfail $? "decompress binutils archive" || { return 1; }


    log_info "Decompressing gcc archive"
    if [ -d "${gcc_build}" ]; then
        rm -rf gcc-${gcc_build}
    fi
    xz -d -T $(cpu_count) -c ${gcc_archive} | tar -x >>${build_log} 2>&1
    log_passfail $? "decompress gcc archive" || { return 1; }


    log_info "Decompressing gdb archive"
    if [ -d "${gdb_build}" ]; then
        rm -rf gdb-${gdb_build}
    fi
    xz -d -T $(cpu_count) -c ${gdb_archive} | tar -x >>${build_log} 2>&1
    log_passfail $? "decompress gdb archive" || { return 1; }



    log_info "Configuring binutils for ${TARGET}..."
    cd ${build_src}
    mkdir ${binutils_build}
    cd ${binutils_build}
    ../${binutils_src}/configure --target=$TARGET --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror >>${build_log} 2>&1
    log_passfail $? "configure binutils" || { return 1; }

    log_info "Building binutils..."
    make -j $(cpu_count) >>${build_log} 2>&1
    log_passfail $? "build binutils" || { return 1; }

    log_info "Installing binutils"
    make install >>${build_log} 2>&1
    log_passfail $? "install binutils" || { return 1; }

    log_info "Obtaining gcc pre-requisites..."
    cd ${build_src}/${gcc_src}
    ./contrib/download_prerequisites >>${build_log} 2>&1
    log_passfail $? "obtaining gcc pre-requisites" || { return 1; }

    log_info "Configuring gcc for ${TARGET}..."
    cd ${build_src}
    mkdir ${gcc_build}
    cd ${gcc_build}

    ../${gcc_src}/configure --target=$TARGET \
                            --prefix="$PREFIX" \
                            --disable-nls \
                            --enable-languages=c,c++ \
                            --without-headers \
                            >>${build_log} 2>&1

    log_passfail $? "configure gcc" || { return 1; }

    log_info "Building gcc..."
    make -j $(cpu_count) all-gcc >>${build_log} 2>&1
    log_passfail $? "build gcc" || { return 1; }

    log_info "Building libgcc..."
    make -j $(cpu_count) all-target-libgcc >>${build_log} 2>&1
    log_passfail $? "build libgcc" || { return 1; }

    log_info "Installing gcc..."
    make install-gcc >>${build_log} 2>&1
    log_passfail $? "install gcc" || { return 1; }

    log_info "Installing libgcc..."
    make install-target-libgcc >>${build_log} 2>&1
    log_passfail $? "install libgcc" || { return 1; }

    log_info "Configuring gdb for ${TARGET}..."
    cd ${build_src}
    mkdir ${gdb_build}
    cd ${gdb_build}

    if [[ "$OSTYPE" == "darwin"* ]]; then
        ../${gdb_src}/configure --target=${TARGET} \
                                --prefix="${PREFIX}" \
                                --disable-werror \
                                --with-python=${python_path} \
                                --with-libgmp-prefix="`brew --prefix gmp`" \
                                --with-gmp="`brew --prefix gmp`" \
                                --with-isl="`brew --prefix isl`" \
                                --with-mpc="`brew --prefix libmpc`" \
                                --with-mpfr="`brew --prefix mpfr`" \
                                >>${build_log} 2>&1
    else
        ../${gdb_src}/configure --target=${TARGET} \
                                --prefix="${PREFIX}" \
                                --with-python=${python_path} \
                                >>${build_log} 2>&1
    fi

    log_passfail $? "configure gdb" || { return 1; }

    log_info "Building gdb..."
    make -j $(cpu_count) >>${build_log} 2>&1
    log_passfail $? "build gdb" || { return 1; }

    log_info "Installing gdb"
    make install >>${build_log} 2>&1
    log_passfail $? "install gdb" || { return 1; }
}

main $@
exit $?
