#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
curl -fL https://raw.githubusercontent.com/hardcoverapp/hardcover-docs/main/schema.json -o build/hardcover-schema.json
npm install --prefix build/catalog-schema-tools --no-save --ignore-scripts graphql@16.14.2
