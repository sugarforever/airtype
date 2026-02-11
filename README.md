# Airtype

Voice-to-text macOS utility. Speak naturally and Airtype transcribes and inserts text into any application.

## Development

### Prerequisites

- Xcode 16.4+
- macOS 13.0+

### Build & Run

Open `Airtype.xcodeproj` in Xcode and run the `Airtype` scheme.

## Release Process

Releases are fully automated via CircleCI. A git tag triggers the pipeline which builds, signs, notarizes, and uploads the DMG to Cloudflare R2.

### Steps

1. Tag the release:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

2. CircleCI automatically:
   - Stamps the version from the tag into Info.plist
   - Builds a Release archive with Developer ID signing
   - Exports and notarizes the app with Apple
   - Creates a DMG
   - Uploads to R2 as `Airtype-v0.2.0.dmg` and `Airtype-latest.dmg`

3. Download link:
   - Versioned: `https://pub-9bc27f7ea4884bf89d219798d23f6dd2.r2.dev/releases/Airtype-v0.2.0.dmg`
   - Latest: `https://pub-9bc27f7ea4884bf89d219798d23f6dd2.r2.dev/releases/Airtype-latest.dmg`

### Version Scheme

Follow [semver](https://semver.org):
- **Patch** (v0.1.1) — bug fixes
- **Minor** (v0.2.0) — new features
- **Major** (v1.0.0) — breaking changes or public launch

### CI Environment Variables

Set these in CircleCI project settings:

| Variable | Description |
|---|---|
| `CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application .p12 |
| `CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID email for notarization |
| `APP_SPECIFIC_PASSWORD` | App-specific password for notarization |
| `R2_BUCKET` | Cloudflare R2 bucket name |
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `AWS_ACCESS_KEY_ID` | R2 API token access key |
| `AWS_SECRET_ACCESS_KEY` | R2 API token secret key |
