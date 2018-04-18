#!/bin/bash

# Copyright (c) 2003-2018 Eelco Dolstra and the Nixpkgs/NixOS contributors
# Copyright (c) 2018 SimSpace
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

###############################################################################
# IMPORTANT!!!
#
# The name of this script MUST be prefixed with "ld.". Using this prefix
# exploits how clang looks up the linker path, so we are tricking clang into
# thinking this script is itself a linker. For details on how clang looks up
# the linker path, see this changeset where support for the "-fuse-ld"
# option was added:
#  > https://reviews.llvm.org/diffusion/L/change/cfe/trunk/lib/Driver/ToolChain.cpp;211785
#
###############################################################################
#
# ld.ld-wrapper-macos.sh is only relevant for developers using macOS. To
# install this script, put it somewhere in the PATH and be sure to "chmod +x"
# it.
#
# Here is an example snippet for hpack's package.yaml format showing how to
# tell GHC to use this script:
#
#  when:
#    - condition: os(darwin)
#      ghc-options:
#        - "-optl-fuse-ld=ld-wrapper-macos.sh"
#
# This script wraps the raw "ld" linker to sidestep behavior in macOS Sierra
# and later where the OS prevents loading dynamic libraries that have a mach-o
# header size over a fixed threshold of 32,768. When the size is exceeded and
# GHC goes to dlopen the .dylib, we get a GHC panic that looks like this:
#
# ghc: panic! (the 'impossible' happened)
#   (GHC version 8.2.2 for x86_64-apple-darwin):
#     Loading temp shared object failed: dlopen(/var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib, 5): no suitable image found.  Did find:
#     /var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib: malformed mach-o: load commands size (33208) > 32768
#     /var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib: stat() failed with errno=25
#
# This issue occurs most often when GHC is loading its temporary
# 'libghc_<numbers>.dylib' file that is used as part of Template Haskell
# codegen. This .dylib file dynamically links in just about all of a project's
# dependencies - both direct and indirect - and can easily exceed the mach-o
# header size limit for medium to large-size projects.
#
# Note that macOS does not impose a restriction on the creation of dynamic
# libraries with header sizes over the threshold. In the above GHC panic
# example, the "libghc_13.dylib" file was successfully created. The OS
# restriction comes into play when the library is attempted to be loaded.
#
# There is a stack issue discussing this problem here:
#  > https://github.com/commercialhaskell/stack/issues/2577
#
# There are also GHC trac tickets about this here:
#  > https://ghc.haskell.org/trac/ghc/ticket/12479
#  > https://ghc.haskell.org/trac/ghc/ticket/14444
#
# A workaround exists for this issue in "cabal new-build" via putting all
# dependency libraries in a common store directory and shortening names, but
# it too can still hit the limit:
#  > https://github.com/haskell/cabal/pull/4656
#  > https://github.com/haskell/cabal/issues/5220
#
# The approach we are taking in this script is heavily influenced by the
# changes that went into NixOS to handle the issue. It is largely a straight
# lift with removal/replacement of any Nix-y bits and is simplified
# a good bit to just handle the GHC use case instead of handling all kinds of
# linking outside of GHC too:
#  > https://github.com/NixOS/nixpkgs/pull/27536
#  > https://github.com/NixOS/nixpkgs/pull/38881
#  > https://github.com/tpoechtrager/cctools-port/pull/34
#
# This script recursively re-exports the dependencies by subdividing to create
# a tree of reexporting delegate libraries. For example, here is the contents
# of "<working_dir>/.ld-wrapper-macos/lib" after this script was run
# successfully during TH codegen on a project with 750 direct dependencies:
#
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0-reexport-delegate-1.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1-reexport-delegate-1.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-0-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-0-reexport-delegate-1.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-1.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-1-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-1-reexport-delegate-1.dylib
#
# All of the "leaf" dylibs above (the longest file paths) are the libraries
# that re-export the sub-divided chunks of dependencies.  Each non-"leaf"
# dylib re-exports its two "children" re-exporting dylibs, i.e.:
#
# $ otool -L .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib
# .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib:
#         <working_dir>/.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib (compatibility version 0.0.0, current version 0.0.0)
#         <working_dir>/.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0.dylib (compatibility version 0.0.0, current version 0.0.0)
#         <working_dir>/.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1.dylib (compatibility version 0.0.0, current version 0.0.0)
#
# The actual library GHC is intending to create - in the above example, this
# would be "libghc_13.dylib" - will only link against the two re-exporting
# libraries at the top-most level of the tree, i.e.:
#
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib
#  > .ld-wrapper-macos/lib/libghc_13-reexport-delegate-1.dylib
#
# As each delegate library re-exports its "children" delegate libraries, the
# actual library GHC is intending to create has full access to all the real
# Haskell dependencies re-exported by the "leaf" delegate libraries.
# Most importantly, none of the generated dylibs will have a mach-o header
# size over the limit imposed by macOS.

declare -r DEBUG=false

set -o errexit
set -o pipefail
set -o nounset
[[ "${DEBUG}" == 'true' ]] && set -o xtrace

declare -r OUTPUT_KIND_STATIC_EXECUTABLE="OUTPUT_KIND_STATIC_EXECUTABLE"
declare -r OUTPUT_KIND_DYNAMIC_LIBRARY="OUTPUT_KIND_DYNAMIC_LIBRARY"
declare -r OUTPUT_KIND_DYNAMIC_BUNDLE="OUTPUT_KIND_DYNAMIC_BUNDLE"
declare -r OUTPUT_KIND_DYLD="OUTPUT_KIND_DYLD"
declare -r OUTPUT_KIND_DYNAMIC_EXECUTABLE="OUTPUT_KIND_DYNAMIC_EXECUTABLE"
declare -r OUTPUT_KIND_PRELOAD="OUTPUT_KIND_PRELOAD"
declare -r OUTPUT_KIND_OBJECT_FILE="OUTPUT_KIND_OBJECT_FILE"
declare -r OUTPUT_KIND_KEXT_BUNDLE="OUTPUT_KIND_KEXT_BUNDLE"

declare -ri dependencyThreshold=150
declare -i dependencyCount=0

declare -ar origArgs=("$@")

# Throw away what we won't need
declare -a parentArgs=()

declare -a childrenLookup=()
declare -a childrenInputs=()

declare outputKind=''
declare macOSXVersionMin='10.13.0'

while (( $# )); do
    case "$1" in
        -static)
            outputKind=$OUTPUT_KIND_STATIC_EXECUTABLE
            parentArgs+=("$1")
            shift 1
            ;;
        -dylib)
            outputKind=$OUTPUT_KIND_DYNAMIC_LIBRARY
            parentArgs+=("$1")
            shift 1
            ;;
        -bundle)
            outputKind=$OUTPUT_KIND_DYNAMIC_BUNDLE
            parentArgs+=("$1")
            shift 1
            ;;
        -dylinker)
            outputKind=$OUTPUT_KIND_DYLD
            parentArgs+=("$1")
            shift 1
            ;;
        -execute)
            outputKind=$OUTPUT_KIND_DYNAMIC_EXECUTABLE
            parentArgs+=("$1")
            shift 1
            ;;
        -preload)
            outputKind=$OUTPUT_KIND_PRELOAD
            parentArgs+=("$1")
            shift 1
            ;;
        -r)
            outputKind=$OUTPUT_KIND_OBJECT_FILE
            parentArgs+=("$1")
            shift 1
            ;;
        -kext)
            outputKind=$OUTPUT_KIND_KEXT_BUNDLE
            parentArgs+=("$1")
            shift 1
            ;;
        -macosx_version_min)
            macOSXVersionMin="$2"
            parentArgs+=("$1" "$2")
            shift 2
            ;;
        -l)
            echo "ld-wrapper-macos: ld does not support '-l foo'" >&2
            exit 1
            ;;
        -lto_library)
            parentArgs+=("$1" "$2")
            shift 2
            ;;
        -framework)
            parentArgs+=("$1" "$2")
            shift 2
            ;;
        -lazy_library | -reexport_library | -upward_library | -weak_library)
            echo "ld-wrapper-macos: -lazy_library | -reexport_library | -upward_library | -weak_library are not supported" >&2
            exit 1
            ;;
        -lazy-l* | -upward-l* | -weak-l*)
            echo "ld-wrapper-macos: -lazy-l* | -upward-l* | -weak-l* are not supported" >&2
            exit 1
            ;;
        *.so.* | *.dylib)
            echo "ld-wrapper-macos: *.so.* | *.dylib are not supported" >&2
            exit 1
            ;;
        -l*)
            dependencyCount+=1
            childrenInputs+=("-reexport$1")
            shift 1
            ;;
        -reexport-l*)
            dependencyCount+=1
            childrenInputs+=("$1")
            shift 1
            ;;
        *.a | *.o)
            parentArgs+=("$1")
            shift 1
            ;;
        -L | -F)
            # Evidentally ld doesn't like using the child's RPATH, so it still
            # needs these.
            parentArgs+=("$1" "$2")
            shift 2
            ;;
        -L?* | -F?*)
            parentArgs+=("$1")
            childrenLookup+=("$1")
            shift 1
            ;;
        -o)
            outputName="$2"
            parentArgs+=("$1" "$2")
            shift 2
            ;;
        -install_name | -dylib_install_name | -dynamic-linker | -plugin)
            parentArgs+=("$1" "$2")
            shift 2
            ;;
        -rpath)
            # Only an rpath to the child is needed, which we will add
            shift 2
            ;;
        *)
            parentArgs+=("$1")
            shift 1
            ;;
    esac
done

if (( "$dependencyCount" <= "$dependencyThreshold" )); then
    [[ "${DEBUG}" == 'true' ]] && echo "ld-wrapper-macos: Only ${dependencyCount} inputs counted while ${dependencyThreshold} is the ceiling, linking normally." >&2
    exec ld "${origArgs[@]}"
fi

[[ "${DEBUG}" == 'true' ]] && echo "ld-wrapper-macos: ${dependencyCount} inputs counted when ${dependencyThreshold} is the ceiling, inspecting further. " >&2

if [ "$outputKind" != "$OUTPUT_KIND_DYNAMIC_LIBRARY" ]; then
    [[ "${DEBUG}" == 'true' ]] && echo "ld-wrapper-macos: Output kind of '${outputKind}' specified but script only supports '${OUTPUT_KIND_DYNAMIC_LIBRARY}', linking normally." >&2
    exec ld "${origArgs[@]}"
fi

declare -r curDir=$(pwd)
declare -r outDir="$curDir/.ld-wrapper-macos"

if [[ $outputName != *reexport-delegate* ]]; then
    # Do some cleanup of the script's output directory generated by the
    # previous execution of the script. We know we are in the initial
    # call to the script here and not in a subsequent recursive call.
    if [ -d "$outDir" ]; then rm -rf $outDir; fi
fi

mkdir -p "$outDir/lib"
mkdir -p "$outDir/obj"

declare -r outputNameLibless=$( \
    if [[ -z "${outputName}" ]]; then
        echo unnamed
        return 0;
    fi
    baseName=$(basename ${outputName})
    if [[ "$baseName" = lib* ]]; then
        baseName="${baseName:3}"
    fi
    finalName=$(echo $baseName | cut -f 1 -d '.')
    echo "$finalName")

declare -ra children=(
    "$outputNameLibless-reexport-delegate-0"
    "$outputNameLibless-reexport-delegate-1"
)

symbolBloatObject=$outDir/obj/$outputNameLibless-symbol-hack.o
if [[ ! -f $symbolBloatObject ]]; then
    # `-Q` means use GNU Assembler rather than Clang, avoiding an awkward
    # dependency cycle.
    printf '.private_extern _______child_hack_foo\nchild_hack_foo:\n' |
        as -Q -- -o $symbolBloatObject
fi

# First half of libs
ld.ld-wrapper-macos.sh -macosx_version_min "$macOSXVersionMin" -arch x86_64 -dylib \
    -o "$outDir/lib/lib${children[0]}.dylib" \
    -install_name "$outDir/lib/lib${children[0]}.dylib" \
    "${childrenLookup[@]}" "$symbolBloatObject" \
    "${childrenInputs[@]:0:$((${#childrenInputs[@]} / 2 ))}"

# Second half of libs
ld.ld-wrapper-macos.sh -macosx_version_min "$macOSXVersionMin" -arch x86_64 -dylib \
    -o "$outDir/lib/lib${children[1]}.dylib" \
    -install_name "$outDir/lib/lib${children[1]}.dylib" \
    "${childrenLookup[@]}" "$symbolBloatObject" \
    "${childrenInputs[@]:$((${#childrenInputs[@]} / 2 ))}"

parentArgs+=("-L$outDir/lib" -rpath "$outDir/lib")
if [[ $outputName != *reexport-delegate* ]]; then
    parentArgs+=("-l${children[0]}" "-l${children[1]}")
else
    parentArgs+=("-reexport-l${children[0]}" "-reexport-l${children[1]}")
fi

[[ "${DEBUG}" == 'true' ]] && echo "flags using delegated children to ld:" >&2
[[ "${DEBUG}" == 'true' ]] && printf "  %q\n" "${parentArgs[@]}" >&2

exec ld "${parentArgs[@]}"
