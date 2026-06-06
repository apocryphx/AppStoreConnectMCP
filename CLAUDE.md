# AppStoreConnect-Bridge — CLAUDE.md

## What this project is

A **native macOS MCP server** (Model Context Protocol bridge) that exposes App Store Connect API and iTunes Search API as tools callable from Claude Desktop. Distributed as a double-click-installable `.mcpb` bundle. No Node.js, no Python — pure Objective-C + Foundation/Security frameworks.

**Owner:** Kolja Wawrowsky (kolja.wawrowsky@gmail.com)  
**Bundle identifier:** `com.apocryphx.appstoreconnect-bridge`  
**Keychain service name:** `com.apocryphx.appstoreconnect-bridge`

---

## Architecture

```
Claude Desktop ──stdio──► AppStoreConnect_Bridge.app (macOS)
                               │
                               ├── MCPServer.m          JSON-RPC 2.0 dispatcher
                               ├── ASCToolRegistry.m    tool list + routing
                               │
                               ├── Auth/
                               │   ├── ASCCredentialStore.m   Keychain r/w
                               │   └── ASCJWTSigner.m         ES256 JWT (PKCS#8→X9.63)
                               │
                               ├── API/
                               │   └── ASCClient.m            REST client (GET/POST/PATCH)
                               │
                               └── Tools/
                                   ├── ASCAppsTools.m          list_apps, get_app_info
                                   ├── ASCBetaTools.m          TestFlight groups/testers/feedback
                                   ├── ASCBundleIDTools.m      bundle IDs + capabilities
                                   ├── ASCDeviceTools.m        registered devices
                                   ├── ASCKeywordTools.m       iTunes Search API (no auth)
                                   ├── ASCLocalizationTools.m  versions + localizations
                                   ├── ASCReportsTools.m       analytics/sales/finance reports
                                   ├── ASCUserTools.m          team users
                                   └── ASCXcodeTools.m         Xcode Cloud schemas/builds
```

Transport: **JSON-RPC 2.0 over stdin/stdout** (standard MCP stdio mode).  
`MCPFraming.m` handles Content-Length framing.

---

## Credentials & Keychain

Credentials are stored in the macOS Keychain under service `com.apocryphx.appstoreconnect-bridge`:

| Keychain account | Contents |
|---|---|
| `keyId` | App Store Connect API Key ID (e.g. `T8NPC364Z9`) |
| `issuerId` | Issuer ID (e.g. `ba8c95f3-281e-4d6e-89dd-c85b4b89cd7e`) |
| `p8Data` | .p8 private key contents (PEM string) |
| `vendorNumber` | iTunes Connect vendor number (for reports) |

**Setup flow:**
1. User calls `configure_app_store_connect` tool with `key_id`, `issuer_id`, `p8_path`, optional `vendor_number`
2. Bridge reads and stores all values in Keychain, then **auto-deletes the .p8 file from disk**
3. All other tools become available immediately (no restart needed)

The bridge shows only `configure_app_store_connect` until credentials are present; then all tools are visible.

**To generate an API key:** App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → (+). Download the .p8 once (Apple only shows it once).

---

## JWT Authentication (critical implementation detail)

Apple's .p8 files are **PKCS#8 DER** format. macOS `SecKeyCreateWithData` requires **X9.63** format (04‖Qx‖Qy‖d, 97 bytes). These are different — passing PKCS#8 returns `OSStatus -50 (errSecParam)`.

**The fix lives in `ASCJWTSigner.m → _x963KeyFromPKCS8:`**

Parsing sequence:
1. Outer PKCS#8 SEQUENCE → skip
2. `version INTEGER 0` → skip
3. `AlgorithmIdentifier SEQUENCE` → skip entirely
4. `OCTET STRING` → enter (this wraps the SEC1 ECPrivateKey)
5. SEC1 `SEQUENCE` → enter
6. `version INTEGER 1` → skip
7. `OCTET STRING` (32 bytes) → read as `d` (private scalar)
8. **`[0] ECParameters` (tag 0xA0)** → skip if present (Apple includes it, many parsers miss this)
9. `[1] BIT STRING` (tag 0xA1) → 66 bytes: `00 04 Qx Qy`, extract `04‖Qx‖Qy` (65 bytes)
10. Assemble X9.63: `[04‖Qx‖Qy (65)] ‖ [d (32)]` = 97 bytes

JWT claims: `iss` (issuerId), `iat` (now), `exp` (now+20min), `aud: "appstoreconnect-v1"`, `bid` (bundle ID filter optional).

---

## Build & Pack

```bash
# Build
xcodebuild -project AppStoreConnectMCP.xcodeproj \
           -scheme AppStoreConnectMCP \
           -configuration Release \
           -destination 'platform=macOS' build

# Pack into .mcpb
cd bundle
npx @anthropic-ai/mcpb pack
# Output: bundle/bundle.mcpb

# Copy to project root
cp bundle/bundle.mcpb AppStoreConnect-Bridge.mcpb

# Install: double-click AppStoreConnect-Bridge.mcpb in Finder (opens Claude Desktop installer)
```

The `bundle/manifest.json` defines the tool and is the `mcpb pack` target. Always run `pack` from `bundle/`, not from the project root.

---

## Auth Smoke Test (no reinstall needed)

```bash
# Compile and run in ~2s — tests full auth chain without touching Claude Desktop
bash scripts/test-auth.sh
```

`scripts/test-auth.m` is a standalone Objective-C file. It loads Keychain credentials, parses the .p8, constructs a JWT, and hits `GET /v1/apps`. If you see 3 app names, auth is working.

---

## Tool Inventory (~38 tools)

### No-auth tools (iTunes Search API, public)
| Tool | What it does |
|---|---|
| `check_keyword_rankings` | Check your app's rank for a list of keywords |
| `search_keyword_competition` | Show top N apps for a keyword with full detail |
| `bulk_keyword_scan` | Table scan: keyword × rank + top 2 competitors |

### App Store Connect API tools
| Category | Tools |
|---|---|
| Apps | `list_apps`, `get_app_info` |
| Versions & Localizations | `create_app_store_version`, `list_app_store_versions`, `list_app_store_version_localizations`, `get_app_store_version_localization`, `update_app_store_version_localization` |
| Beta / TestFlight | `list_beta_groups`, `list_group_testers`, `add_tester_to_group`, `remove_tester_from_group`, `list_beta_feedback_screenshots`, `get_beta_feedback_screenshot` |
| Bundle IDs | `list_bundle_ids`, `get_bundle_id_info`, `create_bundle_id`, `enable_bundle_capability`, `disable_bundle_capability` |
| Devices | `list_devices` |
| Users | `list_users` |
| Xcode Cloud | `list_schemes` (Xcode Cloud workflows) |
| Reports | `download_sales_report`, `download_finance_report`, `create_analytics_report_request`, `list_analytics_reports`, `list_analytics_report_segments`, `download_analytics_report_segment` |

### Important API endpoint notes
- `list_app_store_versions`: uses **`GET /apps/{id}/appStoreVersions`** (relationship endpoint). The top-level `GET /appStoreVersions?filter[app]=` returns 403.
- `list_app_store_version_localizations`: uses **`GET /appStoreVersions/{id}/appStoreVersionLocalizations`** for the same reason.

---

## Owner's Apps

| App | Bundle ID | App ID | Platform |
|---|---|---|---|
| ES Memory MCP | — | — | macOS |
| AI Server | — | — | macOS |
| Sketchography | `com.koljaw.Sketchography` | `6526502527` | iOS + macOS |

---

## Sketchography ASO Work (completed)

**What was done:**
- Audited current keyword field: `Learn to draw, Photo to sketch, Digital drawing, Sketch, Draw` (61/100 chars — wasted on unwinnable single words)
- Ran bulk keyword scans across 16+ photo-to-sketch terms
- Key finding: `photo outline` — #1 competitor is "Outline Photo" at ★3.0 with 2 ratings (highly winnable)
- Created iOS v1.0.6 (PREPARE_FOR_SUBMISSION) — keywords can't be edited on READY_FOR_SALE versions
- Updated v1.0.6 en-US keywords to: `photo outline,sketch from photo,pencil sketch,drawing from photo,pencil effect,portrait sketch,trace` (exactly 100 chars)

**Pending for Sketchography:**
- Attach a build to v1.0.6 and submit when ready
- Re-run `check_keyword_rankings` after 2-3 weeks live to measure movement
- Biggest ranking lever: getting even 5-10 reviews (★0.0 with 0 ratings hurts all rankings)

---

## Pending Project Tasks

- **GitHub release**: push commits, create v1.0.0 tag, attach `AppStoreConnect-Bridge.mcpb` as release asset
- **Mac version keywords**: v1.0 MAC_OS is in PREPARE_FOR_SUBMISSION — keywords not yet optimised
- Consider adding `update_app_info` tool for editing app-level metadata (subtitle, privacy URL, etc.)

---

## Known Gotchas

1. **PKCS#8 vs X9.63** — Already fixed. Don't revert or "simplify" `_x963KeyFromPKCS8:`. The `[0] ECParameters` skip is required for Apple's .p8 files.
2. **Collection vs relationship endpoints** — Several ASC resources return 403 on top-level `GET /resource?filter[parent]=id`. Always use `GET /parent/{id}/resource` (relationship endpoint).
3. **READY_FOR_SALE is locked** — Metadata edits (keywords, description, etc.) require creating a new version in PREPARE_FOR_SUBMISSION first.
4. **Unicode in tool output** — Use `col()` helper in ASCKeywordTools.m (character-based padding) not `%-Ns` printf format (byte-width, garbles multi-byte UTF-8).
5. **mcpb pack must run from `bundle/`** — Running from project root fails with "no manifest.json found".
6. **Apple Search Ads API** — Not available for individual developers (only team accounts). Use iTunes Search API instead for keyword data.
