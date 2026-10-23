# Softcover

A lightweight, native [Hardcover.app](https://hardcover.app) client for iOS written in Swift. 

## Features

- Browse trending books, upcoming releases, community lists, and next-in-series suggestions
- Search by title, author, or ISBN barcode, with local search history
- Manage Want to Read, Reading, Paused, Read, Did Not Finish, and Owned shelves
- Choose, reorder, and swipe between visible library shelves
- Track page, time, or percentage progress, including backdated entries
- Run persistent focus sessions with a Live Activity and Dynamic Island controls, then review or correct the session history
- Set reading deadlines and see the daily pace needed to finish on time
- View goals, streaks, activity statistics, and a genre/author Reading Atlas
- Record multiple reads, ratings, reviews, quotes, personal tags, and community tags
- Create public or private custom lists with duplicate-name protection
- Share customizable book and statistics cards
- Hide and restore unwanted book or series recommendations
- Queue progress and library changes while offline and sync them after reconnecting
- Full audiobook support with hour:minute time tracking
- Release notifications for upcoming books
- Home screen widgets for progress, goals, releases, quotes, trending books, and a random pick
- Update reading progress directly from the Currently Reading widget
- Free themes, palettes, shelf behavior, streak visibility, and date-format preferences
- Multi-language support (English & Swedish)

All reading, library, statistics, sharing, sync, and widget features are free. The optional
Supporter Pack and tips fund development; purchases never gate functional features.

## Requirements

- Xcode 15.0 or later
- iOS 17.0 or later
- A [Hardcover.app](https://hardcover.app) account

## Hardcover Sign-In

Softcover uses Hardcover OAuth with Authorization Code + PKCE. Access and
rotating refresh tokens are stored in a shared iOS Keychain access group so the
app and widgets can use the same session. Existing personal API keys remain
supported as a migration/development fallback and are also stored in Keychain.

To configure a source build:

1. Create a Hardcover Developer App of type **Mobile, desktop, or CLI**.
2. Register `softcover://oauth/callback` as its callback URI and disable the
   device grant.
3. Register the scopes listed in
   `HardcoverOAuthConfiguration.scopes`.
4. Set `HARDCOVER_OAUTH_CLIENT_ID` for both the Softcover app and widget target.

Native clients do not use or ship a client secret.

## Building and Running

### Using Xcode

1. **Clone the repository**
   ```bash
   git clone https://github.com/komadorirobin/Softcover.git
   cd Softcover
   ```

2. **Open the project**
   ```bash
   open "Softcover.xcodeproj"
   ```
   Or simply double-click `Softcover.xcodeproj` in Finder

3. **Select your target device**
   - In Xcode, select your iPhone or iPad from the device dropdown (top toolbar)
   - Or choose "Any iOS Device" to build for physical devices
   - Or select an iOS Simulator

4. **Build and run**
   - Press `Cmd + R` or click the Play button
   - For physical devices, you'll need to:
     - Connect your device via USB or WiFi
     - Trust your development certificate on the device
     - Enable Developer Mode (Settings → Privacy & Security → Developer Mode)

5. **First launch setup**
   - When you first open the app, choose **Connect with Hardcover**
   - Approve the requested access on Hardcover
   - Softcover returns to the app and starts syncing your library and widgets

### Building from Command Line

```bash
# Build for simulator
xcodebuild -project Softcover.xcodeproj -scheme "Hardcover Reading Widget" -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for device (requires signing configuration)
xcodebuild -project Softcover.xcodeproj -scheme "Hardcover Reading Widget" -destination 'generic/platform=iOS' build
```

## Project Structure

- **Hardcover Reading Widget/** - Main iOS app
  - `ContentView.swift` - Main book list and progress tracking UI
  - `SearchBooksView.swift` - Book search functionality
  - `ApiKeySettingsView.swift` - Settings and configuration
  - `HardcoverService*.swift` - API client for Hardcover GraphQL API
  - `StatsView.swift` - Reading statistics and goals
- **ReadingProgressWidget/** - Home screen widgets
  - `ReadingProgressWidget.swift` - Main widget implementation
  - `ReadingGoalWidget.swift` - Reading goal widget

## Troubleshooting

**"Failed to build" errors:**
- Make sure you have Xcode 15.0 or later installed
- Clean build folder: Product → Clean Build Folder (Cmd + Shift + K)
- Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`

**Code signing issues:**
- Open the project in Xcode
- Select the project in the navigator
- Go to "Signing & Capabilities" tab
- Change the Team to your Apple Developer account
- Change the Bundle Identifier to something unique

**Widget not appearing:**
- Make sure the widget extension is enabled in your build scheme
- Check that you have the correct App Group configured
- Try removing and re-adding the widget from the home screen

## Contributing

Contributions are welcome! Feel free to:
- Report bugs by opening an issue
- Suggest new features
- Submit pull requests

## License

This project is open source. Please check the LICENSE file for details.

## Acknowledgments

Built with love for the [Hardcover.app](https://hardcover.app) community.
