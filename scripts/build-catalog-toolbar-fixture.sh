#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app=build/CatalogToolbarFixture.app
mkdir -p "$app"
build/catalog-editing-checks --fixtures > "$app/catalog-fixtures.json"
/usr/libexec/PlistBuddy -c 'Clear dict' "$app/Info.plist"
/usr/libexec/PlistBuddy \
  -c 'Add :CFBundleExecutable string CatalogToolbarFixture' \
  -c 'Add :CFBundleIdentifier string app.softcover.catalog-toolbar-fixture' \
  -c 'Add :CFBundleName string CatalogToolbarFixture' \
  -c 'Add :CFBundleVersion string 1' \
  -c 'Add :CFBundleShortVersionString string 1.0' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :MinimumOSVersion string 18.5' \
  -c 'Add :UIDeviceFamily array' \
  -c 'Add :UIDeviceFamily:0 integer 1' \
  -c 'Add :UILaunchScreen dict' "$app/Info.plist"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
SDKROOT="$sdk" xcrun swiftc -target arm64-apple-ios18.5-simulator \
  -sdk "$sdk" -parse-as-library \
  "Hardcover Reading Widget/CatalogModels.swift" \
  "Hardcover Reading Widget/CatalogService.swift" \
  "Hardcover Reading Widget/CatalogEditorView.swift" \
  "Hardcover Reading Widget/CatalogPickers.swift" \
  ReadingProgressWidget/BookProgress.swift Tests/CatalogToolbarFixture.swift \
  -o "$app/CatalogToolbarFixture"
xcrun xcstringstool compile Localizable.xcstrings --output-directory "$app"
