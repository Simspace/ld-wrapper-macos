# ld-wrapper-macos

## Synopsis

This script wraps the raw "ld" linker to sidestep behavior in macOS Sierra and later where the OS prevents loading dynamic libraries that have a mach-o header size over a fixed threshold of 32,768. When the size is exceeded and GHC goes to dlopen the .dylib, we get a GHC panic that looks like this:

```
ghc: panic! (the 'impossible' happened)
  (GHC version 8.2.2 for x86_64-apple-darwin):
    Loading temp shared object failed: dlopen(/var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib, 5): no suitable image found.  Did find:
    /var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib: malformed mach-o: load commands size (33208) > 32768
    /var/folders/49/bgbzql7j62j5z2r1r0m2m3rr0000gn/T/ghc763_0/libghc_13.dylib: stat() failed with errno=25
```

This issue occurs most often when GHC is loading its temporary 'libghc_<numbers>.dylib' file that is used as part of Template Haskell codegen. This .dylib file dynamically links in just about all of a project's dependencies - both direct and indirect - and can easily exceed the mach-o header size limit for medium to large-size projects.

Note that macOS does not impose a restriction on the creation of dynamic libraries with header sizes over the threshold. In the above GHC panic example, the "libghc_13.dylib" file was successfully created. The OS restriction comes into play when the library is attempted to be loaded.

