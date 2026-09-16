#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: bash tool/verify_real_epub.sh INPUT.epub NEW_OUTPUT_DIRECTORY\n' >&2
  exit 64
fi

# Resolve caller paths before changing to the repository directory.
export REAL_EPUB_INPUT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
case "$2" in
  /*) export REAL_EPUB_OUTPUT="$2" ;;
  *) export REAL_EPUB_OUTPUT="$PWD/$2" ;;
esac
if [[ ! -f "$REAL_EPUB_INPUT" || -e "$REAL_EPUB_OUTPUT" ]]; then
  printf 'Input must be a file and output directory must not exist.\n' >&2
  exit 1
fi

cd "$(dirname "$0")/.."
flutter="${FLUTTER_BIN:-flutter}"
# These suites consume the previous suite's outputs; never run in parallel.
"$flutter" test test/real_book_all_features_test.dart --reporter expanded
"$flutter" test test/real_book_workflows_test.dart --reporter expanded
"$flutter" test test/real_book_reader_test.dart --reporter expanded
