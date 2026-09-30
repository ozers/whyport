# Shipping WhyPort through Apple

WhyPort is distributed **outside the Mac App Store**: a notarized DMG from GitHub Releases (and optionally Homebrew). That is the official Apple path that keeps the app fully working.

## Why not the Mac App Store

Mac App Store apps must enable **App Sandbox**. WhyPort’s job is to:

- inspect other processes with `lsof` / `ps`
- stop / restart your own servers
- call `docker` when present
- open arbitrary project folders in editors and terminals

Those capabilities are incompatible with a sandboxed App Store build. Shipping there would mean a hollow app. Direct distribution with a **Developer ID Application** certificate and **notarization** is what Apple expects for this class of developer tool (same model as many menu-bar utilities).

## What “official” looks like for users

1. You set the GitHub secrets below once.
2. You push a version tag (`v0.1.1`, …).
3. The Release workflow signs the universal `.app` with hardened runtime, packs `WhyPort.dmg`, submits it to Apple’s notary service, staples the ticket, and publishes the GitHub release.
4. Users download the DMG, drag WhyPort to Applications, and open it. Gatekeeper accepts it — no **Open Anyway**, no `xattr`.

Without the secrets, the same workflow still publishes an ad-hoc signed DMG (fine for you; other Macs will show the quarantine warning).

## One-time setup

You need an [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year).

### 1. Register the App ID

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

- Identifier: `dev.whyport.app` (must match `app/Info.plist`)
- Description: WhyPort
- Capabilities: none required for Developer ID distribution

### 2. Create a Developer ID Application certificate

On a Mac with Xcode:

1. Xcode → Settings → Accounts → your team → **Manage Certificates…**
2. **+** → **Developer ID Application**
3. In Keychain Access, select that certificate **and** its private key
4. File → Export Items… → `whyport-developer-id.p12` (set a strong password)

Encode it for GitHub:

```bash
base64 -i whyport-developer-id.p12 | pbcopy
```

### 3. App-specific password

At [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords, create one named `WhyPort notarytool`.

### 4. Team ID

On [developer.apple.com/account](https://developer.apple.com/account) — Membership details → Team ID (10 characters).

### 5. GitHub repository secrets

Repo → Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | base64 of the `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | password you chose when exporting the `.p12` |
| `APPLE_ID` | Apple ID email of the developer account |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_APP_PASSWORD` | app-specific password from step 3 |

### 6. Ship

```bash
git tag v0.1.1
git push origin v0.1.1
```

Watch the **Release** workflow. The job summary shows whether signing/notarization ran. Download the DMG from the GitHub release and open it on a clean Mac to confirm Gatekeeper is quiet.

## Local notarized build (optional)

On a Mac that already has the Developer ID identity in the login keychain:

```bash
cd app
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  WHYPORT_VERSION=0.1.1 \
  ./build-app.sh --universal --dmg

xcrun notarytool submit .build/WhyPort.dmg \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple .build/WhyPort.dmg
spctl --assess --type open --context context:primary-signature -v .build/WhyPort.dmg
```

## Privacy

- Nothing leaves the Mac except the optional “Check for updates” request to GitHub.
- `PrivacyInfo.xcprivacy` declares no tracking and only the UserDefaults required-reason API (settings).
- A short public privacy note lives in the README under **Is it safe?**

## Homebrew

Each release attaches a filled-in `whyport.rb` cask. After notarization works, you can open a PR to [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) with that file so `brew install --cask whyport` works for everyone.
