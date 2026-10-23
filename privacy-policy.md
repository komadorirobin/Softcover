# Privacy Policy for Softcover

**Last Updated: October 22, 2026**

## Overview

Softcover ("the App") is a native iOS client for Hardcover.app that helps you track your reading progress. This Privacy Policy explains how the App handles your information.

## Information We Collect

### Hardcover Sign-In Credentials
- The App uses Hardcover OAuth to connect your account
- OAuth access and refresh tokens are stored **locally on your device only** using iOS Keychain
- Existing users may continue to use a personal Hardcover API key; it is also stored in Keychain
- Credentials are transmitted only to Hardcover's official authorization and API services

### No Personal Data Collection
We do not collect, store, or transmit any of the following:
- Personal identification information
- Usage analytics or tracking data
- Crash reports or diagnostics
- Device information
- Location data
- Cookies or similar tracking technologies

## How We Use Information

### API Communication
- The App uses your OAuth access token or legacy API key to communicate directly with Hardcover's API (api.hardcover.app)
- All reading data (books, progress, lists, etc.) is retrieved from and stored on Hardcover's servers
- We act solely as a client interface to Hardcover's service

### Local Storage
- Book cover images are temporarily cached on your device for performance
- User preferences (sort orders, settings) are stored locally using iOS UserDefaults
- Widget data is stored in a shared App Group for widget functionality

## Third-Party Services

### Hardcover.app
The App communicates exclusively with Hardcover.app's API. Please review Hardcover's privacy policy at [hardcover.app](https://hardcover.app) for information about how they handle your data.

## Data Retention

- All data is stored locally on your device or on Hardcover's servers
- Disconnecting Hardcover revokes the OAuth refresh token when possible and removes local credentials
- Disconnecting before deletion removes Keychain credentials; iOS may otherwise retain Keychain items for a later reinstall
- Deleting the App removes its caches and ordinary local app data
- To delete your reading data, you must do so through your Hardcover account

## Children's Privacy

The App does not knowingly collect information from children under 13. If you are under 13, please do not use this App without parental consent.

## Your Rights

You have the right to:
- Delete all local data by uninstalling the App
- Disconnect the Hardcover session in Softcover or revoke access through your Hardcover account
- Request information about data stored by Hardcover through their service

## Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be posted on this page with an updated "Last Updated" date.

## Data Security

- OAuth tokens and legacy API keys are stored using iOS Keychain
- All communication with Hardcover uses HTTPS encryption
- No data is shared with third parties other than Hardcover

## International Users

The App can be used worldwide. Data is processed by Hardcover according to their privacy policy and terms of service.

## Contact

For questions about this Privacy Policy or the App:
- GitHub: [github.com/komadorirobin/Softcover](https://github.com/komadorirobin/Softcover)
- Open an issue on the GitHub repository

For questions about your reading data and account:
- Contact Hardcover directly through their website

## Consent

By using Softcover, you consent to this Privacy Policy and agree to its terms.

---

**Note:** This app is an independent client for Hardcover.app and is not officially affiliated with or endorsed by Hardcover.
