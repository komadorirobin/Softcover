#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -parse-as-library \
  "Hardcover Reading Widget/CatalogModels.swift" \
  "Hardcover Reading Widget/CatalogService.swift" \
  Tests/CatalogEditingChecks.swift \
  -o build/catalog-editing-checks
build/catalog-editing-checks
