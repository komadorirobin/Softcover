#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app=build/BookUIFixture.app
mkdir -p "$app"
/usr/libexec/PlistBuddy -c 'Clear dict' "$app/Info.plist"
/usr/libexec/PlistBuddy \
  -c 'Add :CFBundleExecutable string BookUIFixture' \
  -c 'Add :CFBundleIdentifier string app.softcover.book-ui-fixture' \
  -c 'Add :CFBundleName string BookUIFixture' \
  -c 'Add :CFBundleVersion string 1' \
  -c 'Add :CFBundleShortVersionString string 1.0' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :MinimumOSVersion string 26.0' \
  -c 'Add :UIDeviceFamily array' \
  -c 'Add :UIDeviceFamily:0 integer 1' \
  -c 'Add :UIDeviceFamily:1 integer 2' \
  -c 'Add :UILaunchScreen dict' "$app/Info.plist"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
SDKROOT="$sdk" xcrun swiftc -target arm64-apple-ios26.0-simulator -sdk "$sdk" -parse-as-library -D BOOK_UI_FIXTURE \
  ReadingProgressWidget/BookProgress.swift \
  "Hardcover Reading Widget/AsyncCachedImage.swift" \
  "Hardcover Reading Widget/LibraryListStore.swift" \
  "Hardcover Reading Widget/BookTagExtractor.swift" \
  "Hardcover Reading Widget/BookRow.swift" \
  "Hardcover Reading Widget/BookDetailStore.swift" \
  "Hardcover Reading Widget/BookDetailQueries.swift" \
  "Hardcover Reading Widget/Quote.swift" \
  "Hardcover Reading Widget/ReadingProgressEditor.swift" \
  "Hardcover Reading Widget/FinishRateReviewSheet.swift" \
  "Hardcover Reading Widget/BookDetailView.swift" \
  "Hardcover Reading Widget/SearchResultDetailSheet.swift" \
  "Hardcover Reading Widget/TrendingBookDetailSheet.swift" \
  "Hardcover Reading Widget/ContentView.swift" \
  Tests/BookUIFixture.swift -o "$app/BookUIFixture"
xcrun xcstringstool compile Localizable.xcstrings --output-directory "$app"
