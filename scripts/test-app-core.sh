#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -parse-as-library -D SOFTCOVER_CORE_TESTS \
  ReadingProgressWidget/HardcoverNetwork.swift \
  ReadingProgressWidget/BookProgress.swift \
  ReadingProgressWidget/HardcoverModels.swift \
  ReadingProgressWidget/LibraryAPI.swift \
  "Hardcover Reading Widget/BookSearchStore.swift" \
  "Hardcover Reading Widget/LibraryListStore.swift" \
  "Hardcover Reading Widget/WantToReadPresentation.swift" \
  "Hardcover Reading Widget/CommunityQueries.swift" \
  "Hardcover Reading Widget/BookDetailQueries.swift" \
  "Hardcover Reading Widget/Quote.swift" \
  Tests/AppCoreTestSupport.swift \
  Tests/AppCoreChecks.swift \
  -o build/app-core-checks
build/app-core-checks "$@"
