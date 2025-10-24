# Changes Summary

## Recent Fixes (October 2025)

### Fix: HTML Entity Decoding Throughout App
**Issue**: HTML entities like `&#x27;` (apostrophes), `&quot;` (quotes), and others were displaying literally in text instead of as proper characters.

**Fixed in the following locations:**
- **UserProfileView.swift**: User bio text
- **BookDetailView.swift**: Book descriptions (via `normalizedDescription()`)
- **SearchDetailComponents.swift**: Review text
- **ListDetailView.swift**: List descriptions
- **UserListsView.swift**: List descriptions
- **CommunityListsView.swift**: List descriptions (two locations)
- **All other user-facing text**: Applied `.decodedHTMLEntities` extension

**Technical Implementation**:
- Used existing `String.decodedHTMLEntities` extension throughout the codebase
- Ensures all API-sourced text displays properly formatted characters
- Applies to descriptions, reviews, bios, and list metadata

### Fix: iPad Landscape Layout Issues
**Issue**: Navigation views displayed as narrow sidebars in landscape mode on iPad, making content difficult to read and navigate.

**Fixed in the following views:**
- **WantToReadView.swift**: Added `.navigationViewStyle(.stack)`
- **SearchBooksView.swift** (Explore tab): Added `.navigationViewStyle(.stack)`
- **ExplorerView.swift**: Added `.navigationViewStyle(.stack)`

**Technical Implementation**:
- Applied `.navigationViewStyle(.stack)` modifier to force single-column layout
- Prevents default iPad split-view (master-detail) behavior
- Ensures consistent full-width layout across all device orientations
- Note: `NavigationStack` views (like Currently Reading) don't have this issue

**Affected Platforms**: iPad (all sizes) in landscape orientation

---

# Changes Summary: Swedish Book Read Status Feature

## Overview
Implementation av funktion för att visa "Läst" status med datum istället för "Add to Want to Read" och "Mark as Read" knappar för böcker som redan är lästa.

## Modified Files

### 1. BookMetadataService.swift
- Added `fetchFinishedBooksWithDates(for:)` method
- Fetches both finished book IDs and their completion dates
- Uses GraphQL to query `user_books` with `user_book_reads` for `finished_at` timestamps
- Returns `[Int: Date]` dictionary mapping book IDs to read dates

### 2. SearchBooksView.swift
- Changed `readDates` from `[Int: String]` to `[Int: Date]`
- Updated `refreshFinishedFlags()` to use new `fetchFinishedBooksWithDates` method
- Modified `SearchResultsListView` initialization to pass `readDates`

### 3. SearchBooksComponents.swift
- Added `readDates` parameter to `SearchResultsListView`
- Updated `SearchResultRowView` to receive actual read dates instead of `nil`
- The row view already had the logic to display read dates - now it gets real data

### 4. SearchResultDetailSheet.swift
- Added state variables for tracking read status:
  - `@State private var isFinished = false`
  - `@State private var finishedDate: Date?`
  - `@State private var isLoadingFinishedStatus = false`
- Modified view to conditionally show either:
  - `BookActionsView` (for unread books)
  - `BookReadStatusView` (for read books)
- Added `loadFinishedStatus()` method to check book read status
- Updated `loadInitialData()` to include finished status loading

### 5. SearchDetailComponents.swift
- Added `BookReadStatusView` struct
- Displays green checkmark with "Read" text
- Shows formatted completion date if available
- Uses green background styling to indicate positive status

### 6. Tests/BookReadStatusTests.swift (New)
- Added basic unit tests for the new functionality
- Tests `BookReadStatusView` with and without dates
- Tests `BookMetadataService.fetchFinishedBooksWithDates` method

## Localization Strings Used
The following Swedish localization strings are used:
- `NSLocalizedString("Read", comment: "already read badge")`
- `NSLocalizedString("Read", comment: "Book read status")`
- `NSLocalizedString("Finished on:", comment: "Read date prefix")`

## Behavior Changes

### Search Results List (SearchBooksView)
- **Before**: Shows "Quick Add" button for all books
- **After**: 
  - Unread books: Shows "Quick Add" button
  - Read books: Shows green "Read" badge with completion date

### Detail Sheet (SearchResultDetailSheet)
- **Before**: Shows "Add to Want to Read" and "Mark as Read" buttons for all books
- **After**:
  - Unread books: Shows action buttons as before
  - Read books: Shows prominent green "Read" status card with completion date

## Technical Notes

### API Integration
- Uses existing GraphQL endpoint with `user_books` and `user_book_reads` tables
- Queries for `finished_at` timestamp from most recent read entry
- Handles chunked requests for better performance with large book lists

### Date Formatting
- Uses `DateFormatter` with `.medium` date style for consistent Swedish date display
- Uses `ISO8601DateFormatter` for parsing API responses

### Performance Considerations
- Read status is loaded asynchronously in parallel with other data
- Uses concurrent task groups for optimal loading performance
- Caches read dates at the search view level to avoid repeated API calls

## Future Enhancements

1. **Cache Management**: Consider adding local caching for read status to improve performance
2. **Refresh Logic**: Add pull-to-refresh functionality to update read status
3. **Batch Updates**: Optimize API calls when marking books as read in bulk
4. **Offline Support**: Cache read status for offline viewing