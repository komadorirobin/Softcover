#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -parse-as-library \
  ReadingProgressWidget/HardcoverNetwork.swift \
  ReadingProgressWidget/BookProgress.swift \
  ReadingProgressWidget/HardcoverModels.swift \
  ReadingProgressWidget/HardcoverGoalPage.swift \
  ReadingProgressWidget/LibraryAPI.swift \
  "Hardcover Reading Widget/FinishedBookEntry.swift" \
  "Hardcover Reading Widget/CommunityQueries.swift" \
  "Hardcover Reading Widget/HardcoverService+Lists.swift" \
  "Hardcover Reading Widget/HardcoverService+Prompts.swift" \
  "Hardcover Reading Widget/HardcoverService+UserBooks.swift" \
  "Hardcover Reading Widget/SocialListStores.swift" \
  Tests/AppCoreTestSupport.swift Tests/SocialTestSupport.swift Tests/SocialChecks.swift \
  -o build/social-checks
build/social-checks
