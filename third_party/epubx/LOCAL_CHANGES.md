# Local epubx fork

Based on epubx 4.0.0 from pub.dev, with the upstream LICENSE retained.
Use this path dependency rather than editing the pub cache.

Local changes resolve Unicode / percent-escaped resource paths consistently
across OPF, content maps, cover images, NCX and EPUB3 navigation. Paths use POSIX
semantics on every platform. URI suffixes are separated before decoding, and
decoding happens only at the URI-to-ZIP boundary. Navigation state is scoped to
one read rather than shared across books.
WebP images are classified as images so a converted WebP cover remains readable.

Regression coverage: `test/operations/epubx_path_compatibility_test.dart` and
the opt-in real-book reader audit in `test/real_book_workflows_test.dart`.
