# Vendored ZIPFoundation

- Upstream: https://github.com/weichsel/ZIPFoundation
- Tag: 0.9.20
- Revision: `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`
- License: MIT, included in LICENSE.txt. Original source copyright headers retained.
- Module name: `RivoZIPFoundation`, to coexist with the app's remote `ZIPFoundation` module.

Local changes:

1. CZlib is always declared in the enclosing package. Host-side manifest evaluation on macOS must not omit the Android zlib dependency merely because host Compression is available.
2. Explicit conditional Android libc imports; Android uses the same CP437 filename conversion branch as Linux.
3. Android `funopen` callbacks infer Bionic's non-null C signature and forward to the original memory-file stubs. Failed Android `funopen` releases the retained cookie.
4. The nonempty EOCD header's baseAddress is unwrapped for Bionic fwrite's non-null buffer parameter.
5. Android does not compile a call to API-36-only lchmod. The existing non-Darwin symlink attribute path already skips those attributes.

No ZIP representation, compression level, CRC calculation, or document preservation policy was changed. Apple builds retain the upstream Compression backend; Android uses zlib. The package's real-document round trips exercise the memory-backed ZIP reader and writer on both platforms.

For future updates, compare this source directory against the pinned upstream tag and preserve these platform fixes or verify their upstream replacements. Do not replace it with the app's remote package without testing a macOS-to-Android build.
