# Privacy Policy

**App Store Connect Bridge**
Last updated: June 6, 2026

## Overview

App Store Connect Bridge is a native macOS MCP bridge that connects Claude Desktop directly to Apple's App Store Connect API. It does not collect, store, or transmit any data beyond what is necessary to authenticate with and query Apple's official API on your behalf.

## Data Flow

```
Claude Desktop ──stdio──> AppStoreConnect Bridge ──HTTPS──> api.appstoreconnect.apple.com
```

- **Stdio side**: receives JSON-RPC requests from Claude Desktop on stdin, writes responses to stdout. Standard MCP transport.
- **HTTPS side**: forwards authenticated API requests to `api.appstoreconnect.apple.com`. All communication uses TLS. No other hosts are contacted.

## Credential Storage

Your API credentials (Key ID, Issuer ID, and `.p8` private key data) are stored exclusively in your macOS **Keychain** under the service identifier `com.apocryphx.appstoreconnect-bridge`. They are:

- **Never transmitted** except as part of ES256 JWT signatures sent to Apple's API endpoint
- **Never logged** to disk or stderr beyond a non-sensitive startup confirmation
- **Never shared** with any third party

The `.p8` file is automatically deleted from disk after its contents are stored in the Keychain. From that point on, the private key exists only in the Keychain. It is used locally to sign JWTs; the signed token (not the key itself) is included in the `Authorization` header of each API request to Apple.

## Data Collection

The bridge collects **no data**. Specifically:

- **No analytics or telemetry** are sent anywhere
- **No crash reports** are uploaded
- **No usage data** is recorded
- **No data** is shared with third parties other than Apple (via the App Store Connect API, at your direction)

## Files Written

The bridge writes no files during normal operation. No caches, no logs, no preferences files on disk. The only persistent storage is the Keychain entry created when you run `configure_app_store_connect`.

## Network Requests

The only network destination is `api.appstoreconnect.apple.com` (Apple's official API). All requests are made over HTTPS (TLS 1.2+). No other hostnames are contacted.

## Contact

For questions about this privacy policy, open an issue at:
https://github.com/apocryphx/AppStoreConnectMCP/issues
