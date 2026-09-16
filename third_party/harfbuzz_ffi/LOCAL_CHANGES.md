# Bundled font engine

Source (HarfBuzz 14.2.1) and generated bindings are from pub.dev harfbuzz_ffi 0.4.2.
Upstream archive SHA256:
`c54642245610297770d8972dafbc3e330d46772be2860f15977793b6aeb5b937`.
The original package LICENSE and HarfBuzz's COPYING are retained.

Local integration changes:
- Build with native_toolchain_c 0.19.2 instead of native_toolchain_ninja,
  avoiding its incompatible archive 4 dependency.
- Export generated bindings through the public library.
- Keep HarfBuzz thread safety enabled for Flutter background isolates.
- Keep empty `vert`/`vrt2` layout feature markers during pruning. Removing
  a now-empty GPOS `vert` changes vertical shaping fallback in this book's
  CFF font. The synthetic fixture and full-book shaping audit reproduce it.
- Include HarfBuzz's COPYING in the package-level LICENSE for app notices.
- No network downloads or system font libraries are used at build/runtime.
- Normalize imported text line endings and trailing whitespace only.

The native-assets hook compiles and bundles the C++ source for the target OS
and architecture, using Flutter's native compiler toolchain. macOS is tested
locally; Android, iOS, Windows and Linux require their platform build validation.
