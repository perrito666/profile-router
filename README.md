# Profile Router

<img src="Resources/AppIcon.png" width="128" alt="Profile Router icon: two profile badges connected by a branching path on a teal tile">

A small native macOS browser router. Set it as your default browser and send links to Chrome profiles using rules you control.

Written in Swift, with SwiftUI settings and a menu-bar icon. No third-party runtime dependencies.

## Build and run

Requires macOS 13 or later, Google Chrome stable, and Xcode 15 or later (or compatible command-line tools with the macOS SDK).

```sh
swift test
bash scripts/build-app.sh
open 'dist/Profile Router.app'
```

For a universal Intel/Apple Silicon app:

```sh
bash scripts/build-app.sh --arch arm64 --arch x86_64
```

Move the built app to `/Applications` before making it your default browser. Launch it, choose **Set as Default Browser**, and approve macOS's prompt. You can also choose it in **System Settings → Desktop & Dock → Default web browser**. Changing the default is always an explicit user action.

The menu-bar icon opens Settings. Opening the app directly also opens Settings. Receiving a link launches the router without intentionally opening Settings unless there is an error.

## Rules

1. Open Settings, click **Choose Chrome Folder…**, and select `~/Library/Application Support/Google/Chrome` using the macOS folder picker. This grants access to Chrome's profile list; the app remembers the folder permission across launches. Then refresh profiles as needed.
2. Add a rule, select a match type, enter a pattern, and choose a profile.
3. Reorder rules using the arrows. The first enabled match wins.
4. Use **Test URL** to preview draft rules without opening a browser. After saving, **Open Test URL** opens it through the real saved-rule routing path. **Last handoff** shows the most recently received hostname and selected profile, only in memory, so you can distinguish a rule mismatch from a browser-launch problem.
5. Click **Save Rules**. Routing uses saved rules; draft changes do not affect clicked links.

| Match type | Pattern | Meaning |
| --- | --- | --- |
| Hostname glob | `example.com` | That exact hostname, any path or port |
| Hostname glob | `*.example.com` | Subdomains, excluding the bare domain |
| Full URL glob | `https://github.com/ExampleOrg/*` | URLs under that organization path |
| Hostname glob | `*` | Explicit catch-all profile |

Only `*` is a wildcard, matching zero or more characters. Everything else is literal. Matching is anchored to the entire hostname or URL. Hostnames ignore case; full URLs are case-sensitive. Encode spaces in URLs as `%20`. Internationalized hostnames should use their ASCII/punycode form. There is no regular-expression syntax.

Unmatched links go **directly to Google Chrome via NSWorkspace**, bypassing the system default to avoid a routing loop. Chrome chooses the destination, normally the most recently active Chrome window/profile. This is delegated behavior, not independent tracking of window focus. If Chrome is closed, Chrome's startup/profile-picker behavior applies. An exact focus-tracking extension is outside this MVP.

Matching web links use `NSWorkspace.openApplication` with `createsNewApplicationInstance = true` and `--profile-directory=<directory> -- <url>` as launch arguments, without shell interpolation. Chrome's singleton can forward this profile-specific launch to the running browser. The URL is not sent in a separate URL-open Apple Event, which would let Chrome independently choose its last-used profile. If the configured profile is missing, its folder is inaccessible, or its launch fails, the input passes through to Chrome's normal handler. The router does not intentionally create replacement profiles or try a different rule's account.

The app accepts all files and URLs handed to it by macOS. HTTP/HTTPS links can match profile rules. Other inputs, including local HTML files, `mailto:`, and custom schemes, pass through unchanged to Chrome. Pass-through goes directly to Chrome to avoid recursively reopening the router through the system default. Chrome decides what it can display or dispatch. The router does not register itself for every file type or URL scheme, intercept navigation within Chrome, or override apps that explicitly launch a different browser.

## Data and trust

- No network client, analytics, telemetry, crash uploader, or automatic updater in the app.
- No browser extension, Accessibility permission, or AppleScript Automation permission.
- Chrome profile discovery requires a folder grant through the macOS picker. No protected Chrome data is probed before granting access. A read-only security-scoped bookmark is stored locally as `~/Library/Application Support/Profile Router/chrome-folder.bookmark`; if the grant stops working, select the Chrome folder again.
- Reads profile names and directories from `~/Library/Application Support/Google/Chrome/Local State`; it does not read browsing history, cookies, passwords, or page contents.
- Saves rules only to `~/Library/Application Support/Profile Router/config.json`, atomically. No URL history is recorded on disk. The last received hostname, rule, and profile appear in memory for troubleshooting; URL paths and query strings are omitted from that display. Full URLs are passed to Chrome as local launch arguments.
- Invalid or unsupported saved configuration is preserved for manual recovery; incoming files and links pass through to Chrome. Saving is disabled if loading failed.
- The app is not App Sandbox constrained: it needs to discover Chrome profiles and launch Chrome. The source is small enough to audit and build locally.

You can inspect the full routing implementation in `Sources/RouterCore/Routing.swift` and browser launching in `Sources/ProfileRouter/AppModel.swift`.

## Verification

`swift test` covers hostname boundaries, lookalike domains, literal URL matching, case behavior, rule order, disabled rules, non-web pass-through, missing-profile/configuration fallbacks, profile traversal, configuration round trips/version validation, and stale profile discovery.

`python3 scripts/test-url-events.py` checks real macOS URL-event delivery to a freshly launched and already-running app, plus a local HTML file with spaces and Unicode in its filename, without opening Chrome. It also runs in CI. The test targets the app explicitly, so it does not change your default browser. Its explicit test mode records only the generated hostnames and input kind to a temporary file and exits automatically.

For a source-app-specific problem, compare `open 'https://id.atlassian.com/'` with `swift scripts/check-system-browser.swift` in Terminal. The latter uses `NSWorkspace.open(_:configuration:completionHandler:)`, as Electron-based apps do, and reports the selected app path. These checks open the URL through the actual system default; **Open Test URL** calls the router directly and does not check default-browser resolution.

Before relying on routing, check these integration cases on your Mac:

- Two Chrome profiles open: test a matching link for each profile and an unmatched link after switching the active Chrome window.
- Chrome closed: test both a matching and unmatched link, including with Chrome's profile picker enabled.
- Rename/delete a configured profile: refresh and confirm the rule offers a replacement target and affected links pass through to Chrome.
- Restart Profile Router after granting Chrome folder access and confirm profiles still load. Revoke access and confirm Settings offers the folder picker again and affected inputs pass through to Chrome.
- Open a local HTML file with Profile Router and confirm Chrome displays it. Repeat without Chrome folder access to confirm file pass-through does not depend on profile discovery.
- Click several links from another app with the router already running and with it quit.
- Confirm the app appears in the macOS default-browser chooser and both HTTP and HTTPS links reach it.

## Distribution

The CI workflow in `.github/workflows/build.yml` tests and builds a universal app, verifies real macOS URL/file delivery, and uploads a ZIP artifact. It runs on pushes and pull requests.

The release workflow in `.github/workflows/release.yml` follows the signing setup used by [TextChum](https://github.com/perrito666/textchum) and [ClipChum](https://github.com/perrito666/clipchum). Pushing a numeric version tag such as `v0.1.4` builds and publishes a GitHub release with a ZIP, a drag-to-Applications DMG, and SHA-256 checksums. Running it manually on `main` builds the same downloads as workflow artifacts without publishing a release.

Add these repository secrets in **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate exported as a `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that `.p12` |

Then configure **one** notarization credential set, using the same secret names as the other repositories:

| App Store Connect API key | Apple ID alternative |
| --- | --- |
| `APPLE_API_KEY_P8` — `.p8` contents | `APPLE_ID` — account email |
| `APPLE_API_KEY_ID` — key ID | `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password |
| `APPLE_API_ISSUER_ID` — issuer UUID | `APPLE_TEAM_ID` — developer team ID |

With a certificate configured, the workflow requires complete notarization credentials, signs with hardened runtime and the app's bookmark entitlement, notarizes and staples both app and DMG, and verifies the shipping bundle. Temporary signing credentials are removed at the end of the job. A partial signing configuration fails the build. Without a certificate, the downloads remain explicitly labeled as **ad-hoc signed, without Developer ID signing or Apple notarization**. Local `bash scripts/build-app.sh` builds use ad-hoc signing by default.

The icon and its editable drawing source are included. Regenerate the PNG and ICNS using `bash scripts/build-icon.sh`; this uses AppKit, `sips`, and Python's standard library, with no downloaded artwork or image dependencies. The build bundles the icon and MIT license automatically.

## License

[MIT](LICENSE), copyright © 2026 Horacio Duran, including the original app icon.

## Uninstall

Choose Chrome (or another browser) as your default browser first, quit Profile Router, and remove the app. Optionally delete `~/Library/Application Support/Profile Router` to remove rules. Chrome profiles are never deleted by this app.
