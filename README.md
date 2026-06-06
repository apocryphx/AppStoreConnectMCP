# App Store Connect Bridge

A native macOS MCP bridge that gives Claude Desktop **direct access to the App Store Connect API** — no third-party app, no subscription, no Node.js required.

Apple provides the full App Store Connect API free at `api.appstoreconnect.apple.com`. This bridge authenticates using your API key and exposes 35 tools across App management, Beta testing, Localizations, Bundle IDs, Devices, Users, Analytics reports, and Sales & Finance reports.

```
Claude Desktop ──stdio──> AppStoreConnect Bridge ──HTTPS──> api.appstoreconnect.apple.com
   (MCP client)            (native .app, no Dock icon)        (Apple's official API)
```

## Requirements

- macOS 26 or later (Apple Silicon)
- An **App Store Connect API key** (free, created in App Store Connect → Users and Access → Integrations → App Store Connect API)
- Claude Desktop

## Install

### Option 1: Download the `.mcpb` bundle

1. Download [`AppStoreConnect-Bridge.mcpb`](https://github.com/apocryphx/AppStoreConnectMCP/releases/latest/download/AppStoreConnect-Bridge.mcpb)
2. Double-click the file — Claude Desktop opens and installs it automatically
3. Ask Claude to set up your credentials (see below)

### Option 2: Build from source

Requires Xcode and Node (for `npx @anthropic-ai/mcpb pack`).

```bash
git clone https://github.com/apocryphx/AppStoreConnectMCP.git
cd AppStoreConnectMCP
xcodebuild -project AppStoreConnectMCP.xcodeproj -scheme AppStoreConnectMCP -configuration Release build
```

The build's "Package MCPB" run-script phase produces `AppStoreConnect-Bridge.mcpb` at the project root. `scripts/package-mcpb.sh` does the same end-to-end with a clean isolated derived-data path (suitable for release). `scripts/smoke-test.sh` verifies the handshake, `tools/list`, and `tools/call` against a Debug build.

## First-time setup

After installing, tell Claude:

> "Set up my App Store Connect credentials."

Claude will use the `configure_app_store_connect` tool and walk you through providing:

- **Key ID** — 10-character identifier shown in App Store Connect next to your key
- **Issuer ID** — UUID shown at the top of the API keys page
- **Path to your `.p8` file** — downloaded when you created the key (e.g. `~/Downloads/AuthKey_XXXXXXXXXX.p8`)
- **Vendor Number** *(optional)* — required for sales and finance reports

Credentials are stored securely in your macOS Keychain under `com.apocryphx.appstoreconnect-bridge`. **The `.p8` file is automatically deleted from disk** after its contents are stored in the Keychain — the private key then lives only in the Keychain, never on disk.

After setup, Claude immediately has access to all 35 tools. You only configure once.

## Tools

### Apps
| Tool | Description |
|------|-------------|
| `list_apps` | List all apps in your account |
| `get_app_info` | Get details for a specific app |

### Beta Testing
| Tool | Description |
|------|-------------|
| `list_beta_groups` | List TestFlight beta groups |
| `list_group_testers` | List testers in a beta group |
| `add_tester_to_group` | Add a tester to a beta group |
| `remove_tester_from_group` | Remove a tester from a beta group |
| `list_beta_feedback_screenshots` | List crash/feedback screenshots |
| `get_beta_feedback_screenshot` | Get a specific feedback submission |

### App Store Localizations
| Tool | Description |
|------|-------------|
| `create_app_store_version` | Create a new App Store version |
| `list_app_store_versions` | List versions for an app |
| `list_app_store_version_localizations` | List localizations for a version |
| `get_app_store_version_localization` | Get a specific localization |
| `update_app_store_version_localization` | Update description, keywords, or promo text |

### Bundle IDs & Capabilities
| Tool | Description |
|------|-------------|
| `create_bundle_id` | Register a new Bundle ID |
| `list_bundle_ids` | List registered Bundle IDs |
| `get_bundle_id_info` | Get details for a Bundle ID |
| `enable_bundle_capability` | Enable a capability (e.g. Push Notifications) |
| `disable_bundle_capability` | Disable a capability |

### Devices
| Tool | Description |
|------|-------------|
| `list_devices` | List registered devices |

### Users
| Tool | Description |
|------|-------------|
| `list_users` | List team members with roles |

### Analytics & Reports
| Tool | Description |
|------|-------------|
| `create_analytics_report_request` | Create an analytics report request |
| `list_analytics_reports` | List available reports for a request |
| `list_analytics_report_segments` | List download segments for a report |
| `download_analytics_report_segment` | Download and read a report segment |
| `download_sales_report` | Download a sales/trends report |
| `download_finance_report` | Download a finance report |

### Local Tools
| Tool | Description |
|------|-------------|
| `list_schemes` | List Xcode schemes in a local project |

## How it works

Claude Desktop launches the bridge from the unpacked `.mcpb` and speaks JSON-RPC over stdio. The bridge is an `NSApplication` accessory (`LSUIElement=true`) — no Dock icon, no menubar item. Authentication uses ES256 JWTs signed with your `.p8` private key via Apple's Security framework. Tokens are regenerated per-request; no token caching means no clock-skew issues.

The bridge is fully native Objective-C — no openssl, no SPM packages, no Node.js, no Python. The only system frameworks used are Foundation, Security, and AppKit.

## Project structure

```
AppStoreConnectMCP/
├── AppStoreConnectMCP/
│   ├── main.m                          # NSApplication entry, sets up AppDelegate
│   ├── AppDelegate.{h,m}               # lifecycle; starts MCPServer
│   ├── MCPServer.{h,m}                 # serial stdio loop, dispatch, EOF drain
│   ├── MCPFraming.{h,m}                # JSON-RPC 2.0 framing helpers
│   ├── Auth/
│   │   ├── ASCCredentialStore.{h,m}    # Keychain R/W for API credentials
│   │   └── ASCJWTSigner.{h,m}          # ES256 JWT signing via Security.framework
│   ├── API/
│   │   └── ASCClient.{h,m}             # NSURLSession HTTPS client + JSON:API parser
│   ├── Tools/
│   │   ├── ASCToolRegistry.{h,m}       # tool schema list + callTool:arguments:error:
│   │   ├── ASCAppsTools.{h,m}          # App tools
│   │   ├── ASCBetaTools.{h,m}          # Beta testing tools
│   │   ├── ASCLocalizationTools.{h,m}  # Localization tools
│   │   ├── ASCBundleIDTools.{h,m}      # Bundle ID & capability tools
│   │   ├── ASCDeviceTools.{h,m}        # Device tools
│   │   ├── ASCUserTools.{h,m}          # User tools
│   │   ├── ASCReportsTools.{h,m}       # Analytics & sales/finance reports
│   │   └── ASCXcodeTools.{h,m}         # Local Xcode tools
│   ├── AppStoreConnectMCP.entitlements # app-sandbox=false (required for stdio)
│   └── Info.plist                      # LSUIElement=true
├── AppStoreConnectMCP.xcodeproj/
├── bundle/
│   ├── manifest.json                   # MCPB manifest
│   └── icon.png                        # Extension icon
├── scripts/
│   ├── package-mcpb.sh                 # Clean Release build → .mcpb
│   └── smoke-test.sh                   # Handshake / tools/list / tools/call tests
└── icon.png
```

## Privacy

All API calls go directly to `api.appstoreconnect.apple.com` over HTTPS. Your `.p8` private key is stored only in your macOS Keychain and is never transmitted anywhere. See [PRIVACY.md](PRIVACY.md).

## License

MIT — see [LICENSE](LICENSE).
