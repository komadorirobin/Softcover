# App Review Regression Checks

Run from the repository root on a Mac with Xcode command-line tools and Node.js:

~~~sh
sh scripts/prepare-schema-validation.sh
sh scripts/test-app-review.sh
~~~

The preparation step downloads only Hardcover's public GraphQL schema and a pinned
GraphQL validator. The tests intercept networking and isolate UserDefaults; they
do not use an API key, edit the user's library, or write public catalog data.
All subsequent checks can run offline.

## Coverage

- Production transport: HTTP and GraphQL failures, coalescing, queued cancellation,
  surviving shared readers, account isolation, rate limits, cache invalidation,
  and successful writes whose observing task was cancelled.
- Production library/search stores: stable pagination beyond 100 books, reverse
  response order, search clearing, debounce, account changes, and last-good data.
- Format-aware progress, strict release dates, format/language/year presentation,
  and quote page metadata. UIKit HTML entity decoding is explicitly stubbed in the
  core executable; actual web-page parsing is covered by the social fixtures.
- Want to Read release sorting across all pages and after refresh, deterministic
  ties, missing dates, search/filters, and local-day countdowns across time zones,
  midnight, daylight-saving changes, leap days and year boundaries.
- History cancellation and resume, Explore filter races and release intervals,
  malformed versus legitimately empty HTML lists/goals.
- Widget snapshots, selective reload batching, exact deep links, bounded disk cache,
  freshness versus last access, and fallback after failed reads.
- Catalog editing checks documented separately in CatalogEditing.md.
- GraphQL documents checked against the public schema, with no production writes.

## Visual Fixture

~~~sh
sh scripts/build-book-ui-fixture.sh
~~~

Install build/BookUIFixture.app in an iOS simulator. The bundle identifier is
app.softcover.book-ui-fixture. It compiles the production book rows, book detail,
progress editor, review sheet and reading navigation with synthetic covers and
in-memory dependencies. Network access fails closed.

Launch arguments include want-to-read, detail, progress audio dark, finish, large-text,
reduce-motion, offline, social, and save-error. The fixture also asserts
progress-unit correctness and ordering of competing detail loads.

This is not an end-to-end test of real Hardcover permissions, the whole signed-in
app, or WidgetKit's scheduling. Before release, verify live library/edition changes,
VoiceOver traversal, keyboard and touch interaction, device rotation, and widget
refresh on a physical iPhone. Profile scrolling and memory in Instruments with the
same data before and after; synthetic checks do not establish real-device FPS or
battery improvements.
