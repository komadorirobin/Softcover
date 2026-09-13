# Catalog Editing Verification

Run the Foundation model and mocked-network checks without a simulator or API key:

```sh
sh scripts/test-catalog-editing.sh
```

The checks cover librarian-role decoding, sparse mutation payloads, explicit clearing,
ISBN/date/number validation, preserved contributor/series metadata, permission denial,
locked records, changed records, mutation errors and warnings, account changes,
cover imports, and paginated search ranking. No request reaches Hardcover.

## Toolbar Lifecycle Regression

Build the separate simulator fixture with `sh scripts/build-catalog-toolbar-fixture.sh`.
It compiles the production toolbar views with a stub account and intercepts all requests.
Install `build/CatalogToolbarFixture.app` in an iOS simulator and launch
`app.softcover.catalog-toolbar-fixture`. Optional launch arguments are `denied` and
`scope-error`. `switch-account` automatically switches from a non-librarian fixture
to a librarian fixture after one second (expected count: 2, pencil visible).

- Librarian: the on-screen request count must settle at 1 and the pencil must appear.
- `denied`: count 1, no pencil; the permission check must not loop.
- `scope-error`: count 1, an access-error button appears.
- Switch the fixture account: the count increments once and access is checked again.

Before the fix, `.task` was attached to an initially empty `Group` inside a toolbar
item: the request count remained 0 and the pencil never appeared, even for librarians.
Keep the task on the detail view, outside the conditional toolbar content. Removing
the entire toolbar item also avoids an empty glass button for ordinary accounts.

## Rate Limit and Edition Navigation Regression

The Foundation checks also cover `Retry-After` seconds and HTTP dates, the fallback
delay, one automatic read retry, shared per-account cooldowns, long daily limits,
cancellation, account changes during the wait, and no automatic mutation replay.
The overview loads book metadata and nested editions in one HTTP request containing
two top-level queries. Edition fields and lookups load only after choosing an edition.
Schema validation enforces Hardcover's five-top-level-query maximum.

After running the Foundation checks, build the simulator fixture and launch with:

- `editor`: book editor link, current-edition shortcut, and ebook/physical edition rows.
- `editor-rate-limit`: first overview request returns 429, then a five-second countdown
  and the menu appear automatically. Exactly two requests are expected.
- `edition-rate-limit`: the same recovery opens the selected ebook's edit form.
- `editor-daily-limit`: a long cooldown shows a localized error and disabled retry,
  with exactly one request and no automatic loop.

Fixtures intercept all requests and never write public Hardcover data.

## Format-Aware Audio Length

Launch the simulator fixture with `edition`, `edition-physical`, and `edition-audio`.
Only the audiobook must show "Audio length (seconds)". Switching the Format picker
to Audio shows the field immediately; switching to Ebook or Physical hides it.
Switching away and back preserves unsaved duration input without sending that input
for a non-audio format. Existing hidden server metadata is not silently cleared.
Foundation checks cover all these draft transitions, unknown formats, numeric
validation, and sparse duration updates.

To validate the actual Swift GraphQL documents against Hardcover's current schema:

```sh
curl -fL https://raw.githubusercontent.com/hardcoverapp/hardcover-docs/main/schema.json -o build/hardcover-schema.json
npm install --prefix build/catalog-schema-tools --no-save --ignore-scripts graphql
node scripts/validate-catalog-schema.cjs
```

## Manual Account Checks

- Ordinary account: no pencil in book details or search-result details.
- Librarian: open the pencil, edit a book or choose an edition (including audio).
- Scoped key without `read:me:roles`: access error, normal book details still work.
- Scoped key without `write:catalog:edit`: save denied; draft stays open.
- Change the API key while an editor is open: old editor must not save.
- Cancel a changed form or swipe down: discard confirmation / dismissal protection.
- Verify changes against a record you intend to correct. Do not modify public data solely for testing.
- Test a title-only update and ensure unrelated contributors and series remain unchanged.
- Test cover import from a public HTTPS image URL, then choose a book's cover edition.
- If an image import succeeds but the edition save fails, retry reuses the imported image ID within that editor.
- Verify an API rejection, offline save, and successful save followed by a failed refresh.

## API Boundaries

Permissions come from `me.librarian_roles`, never public flair or a hard-coded user.
The current roles decoder accepts an array of role names or a boolean role map;
unknown JSON shapes fail closed. A live account is still needed to confirm the
deployed role representation and mutation behavior. The server remains authoritative
for token scopes and catalog permissions; the public capabilities document does not
reveal an individual token's scopes.

Authors are edition contributions, not edits to the global author record. Series
editing changes book membership and position, not the global series name. Existing
contributor specializations and series details are preserved. Specialized contributor
roles are retained; removing and re-adding a contribution can select a new role.
Edition role choices match Hardcover's editor: Author, Illustrator, Editor,
Translator, Narrator, Foreword, Introduction, Cover Artist and Other, in that order.
IDs come from the server registry; new contributors default to Author when available.
Legacy, unknown and unspecified current roles remain visible but are not selectable
as new values. Opening the editor or editing unrelated fields never normalizes them.

Covers support an existing edition image or URL import using `insert_image`.
There is no local-photo upload endpoint in the documented GraphQL image input.
Book covers use `default_cover_edition_id`.

The latest record is compared before saving. The API exposes no conditional version
argument for these mutations, so this is not an atomic compare-and-swap guarantee.
Image import and edition update are two separate server operations, not a transaction.

Primary references: [official schema](https://github.com/hardcoverapp/hardcover-docs/blob/main/schema.json),
[capabilities](https://api.hardcover.app/capabilities.json),
[search guide](https://github.com/hardcoverapp/hardcover-docs/blob/main/src/content/docs/api/guides/Searching.mdx).
