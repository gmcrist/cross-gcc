# Cross GCC

## Overview

The cross-gcc.sh script helps build a GCC cross compiler that can be used
for cross-platform development.

## Dependencies

The installation script uses functionality provided by the following:
* [https://github.com/gmcrist/shell-toolkit](shell-toolkit)

## Usage

Simply run the script `./cross-gcc` and supply one of the options

| Option    | Description                                                                              |
| --------- | ---------------------------------------------------------------------------------------- |
| help      | Displays usage information                                                               |
| clean     | Removes temporary files in the build directory before building                           |
| clean-all | Removes all temporary files (including downloads) in the build directory before building |
| binutils  | Specifies the version of binutils to build (e.g. 2.37)                                   |
| gcc       | Specifies the version of gcc to build (e.g. 9.4.0)                                       |
| build-dir | Specifies the path to the temporary build location (e.g. /tmp/cross-gcc-build) ld)       |
| prefix    | Specifies the path where cross gcc where will installed (e.g. /usr/cross-gcc/)           |
| target    | Specifies the target architecture and os (e.g. aarch64-linux)                            |

