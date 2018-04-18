# ld-wrapper-macos

Wrapper script around the system `ld` linker for macOS Haskellers to work around Mach-O header size limitations imposed by macOS Sierra and later.

## Installation

1. Copy `ld.ld-wrapper-macos.sh` to a location in the `PATH`.
1. Make the script executable: `chmod +x <path_to_script>/ld.ld-wrapper-macos.sh`
1. In Haskell project files, tell GHC to use the wrapper script as the linker. An example snippet is shown below for `hpack`'s `package.yaml` format.

```yaml
when:
  - condition: os(darwin)
    ghc-options:
      - -optl-fuse-ld=ld-wrapper-macos.sh
```

Optionally, a project's `.gitignore` file can be updated to ignore the working directories used by the wrapper script:

```
# macOS ld wrapper script stuff
.ld-wrapper-macos/
```

## Synopsis

In macOS Sierra and later, the OS prevents loading dynamic libraries that have a Mach-O header size over a fixed threshold of 32,768. When the size is exceeded and GHC goes to `dlopen` the `.dylib`, we get a GHC panic that looks like this:

```
ghc: panic! (the 'impossible' happened)
  (GHC version 8.2.2 for x86_64-apple-darwin):
    Loading temp shared object failed: dlopen(/var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib, 5): no suitable image found.  Did find:
    /var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib: malformed mach-o: load commands size (33208) > 32768
    /var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib: stat() failed with errno=25
```

This issue occurs most often when GHC is loading its temporary `libghc_<numbers>.dylib` file that is used as part of Template Haskell codegen. This `.dylib` file dynamically links in just about all of a project's dependencies - both direct and indirect - and can easily exceed the Mach-O header size limit for medium to large-size projects.

Note that macOS does not impose a restriction on the _creation_ of dynamic libraries with header sizes over the threshold. In the above GHC panic example, the `libghc_13.dylib` file was successfully created. The OS restriction comes into play when the library is attempted to be _loaded_.

The `ld.ld-wrapper-macos.sh` script provided in this repository acts as a "man in the middle" between GHC and the system `ld` linker so that libraries are never generated with header sizes over the limit. For more info on how the script works, please see the [Details](#details) section.

## Example

This repo includes another script - `gen-stack-mega-repo.sh` - that is a slight modification of the script from [this gist](https://gist.github.com/asivitz/f4b983b2374a6155ac4faaf9b61aca59). When `gen-stack-mega-repo.sh` is run, it will generate a huge `stack` megarepo containing a `panic` package and 750 dummy packages that are direct dependencies of `panic`.

The `panic` package uses some Template Haskell, so GHC will be forced to create a temporary `libghc_<numbers>.dylib` that links in all the dummy dependency packages in order to successfully build the `panic` package. Trying to build the megarepo reliably reproduces the GHC panic, especially considering the 750 dummy packages each have names that are over 100 characters long and eat up a massive amount of header size when dynamically linked into the `libghc_<numbers>.dylib` library.

The generated megarepo can be used to test the `ld.ld-wrapper-macos.sh` script:

1. Follow the wrapper script's [installation steps](#installation) so that `ld.ld-wrapper-macos.sh` is available on the `PATH` and is executable.
1. Generate the megarepo: `bash gen-stack-mega-repo.sh`
1. Change directories into the newly created megarepo: `cd panic`
1. Attempt to build the megarepo: `stack build panic` (after a lengthy build of all the dummy dependency packages, the GHC panic should crop up at the end when building the `panic` package itself)
1. Uncomment the `when` condition block in the top-level `package.yaml` project file so that GHC will link with the wrapper script instead of linking using `ld` directly
1. Run `stack build panic` again and this time it should succeed

Note that the above was tested using `stack` version 1.6.3 and GHC version 8.2.2.

## Details

There is a `stack` issue discussing this problem here:
* https://github.com/commercialhaskell/stack/issues/2577

There are also GHC trac tickets about this here:
* https://ghc.haskell.org/trac/ghc/ticket/12479
* https://ghc.haskell.org/trac/ghc/ticket/14444

A different workaround exists for this issue in `cabal new-build` via putting all dependency libraries in a common store directory and shortening names, but it can still hit the limit:
* https://github.com/haskell/cabal/pull/4656
* https://github.com/haskell/cabal/issues/5220

The approach we are taking in this script is _heavily_ influenced by the changes that went into NixOS to handle the issue. It is largely a straight lift with removal/replacement of any Nix-y bits and is simplified a good bit to just handle the GHC use case instead of handling all kinds of linking outside of GHC too:
* https://github.com/NixOS/nixpkgs/pull/27536
* https://github.com/NixOS/nixpkgs/pull/38881
* https://github.com/tpoechtrager/cctools-port/pull/34

This script recursively re-exports the dependencies by subdividing to create a tree of re-exporting delegate libraries. For example, here is the contents of `<working_dir>/.ld-wrapper-macos/lib` after this script was run successfully during TH codegen on the megarepo with 750 direct dependencies from the [Example](#example) section:

```
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0-reexport-delegate-1.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1-reexport-delegate-1.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-0-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-0-reexport-delegate-1.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-1.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-1-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1-reexport-delegate-1-reexport-delegate-1.dylib
```

All of the "leaf" dylibs above (the longest file paths) are the libraries that re-export the sub-divided chunks of dependencies.  Each non-"leaf" dylib re-exports its two "children" re-exporting dylibs, i.e.:

```
$ otool -L .ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib:
        <working_dir>/.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib (compatibility version 0.0.0, current version 0.0.0)
        <working_dir>/.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-0.dylib (compatibility version 0.0.0, current version 0.0.0)
        <working_dir>/.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0-reexport-delegate-1.dylib (compatibility version 0.0.0, current version 0.0.0)
```

The actual library GHC is intending to create - in the above example, this would be `libghc_13.dylib` - will only link against the two re-exporting libraries at the top-most level of the tree, i.e.:

```
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-0.dylib
.ld-wrapper-macos/lib/libghc_13-reexport-delegate-1.dylib
```

As each delegate library re-exports its "children" delegate libraries, the actual library GHC is intending to create has full access to all the real Haskell dependencies re-exported by the "leaf" delegate libraries.  Most importantly, none of the generated dylibs will have a Mach-O header size over the limit imposed by macOS.

---

In the [Installation](#installation) section, the following snippet for `hpack`'s `package.yaml` format was provided to show an example of how to tell GHC to use the wrapper script:

```yaml
when:
  - condition: os(darwin)
    ghc-options:
      - -optl-fuse-ld=ld-wrapper-macos.sh
```

It may look strange in the above snippet that we have told GHC that the linker is `ld-wrapper-macos.sh` when the script in this repository is actually named `ld.ld-wrapper-macos.sh`.

Naming the script with the `ld.` prefix exploits how `clang` looks up the linker path, so we are tricking `clang` into thinking the script is itself a linker. For details on how clang looks up the linker path, see this changeset where support for the `-fuse-ld` option was added:
* https://reviews.llvm.org/diffusion/L/change/cfe/trunk/lib/Driver/ToolChain.cpp;211785
