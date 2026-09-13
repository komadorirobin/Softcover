#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/test-app-core.sh
sh scripts/test-catalog-editing.sh
sh scripts/test-social.sh
node Tests/run-widget-cache-checks.cjs
if [ ! -f build/hardcover-schema.json ] || [ ! -d build/catalog-schema-tools/node_modules/graphql ]; then
  printf '%s\n' 'Schema validation prerequisites are missing. Run: sh scripts/prepare-schema-validation.sh'
  exit 1
fi
node scripts/validate-app-schema.cjs
node scripts/validate-catalog-schema.cjs
node scripts/validate-widget-schema.cjs
