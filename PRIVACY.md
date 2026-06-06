# Privacy Policy

**Astro Bridge**
Last updated: June 6, 2026

## Overview

Astro Bridge is a local connector between Claude Desktop and the Astro app. It does not collect, store, or transmit any data outside your machine.

## Data Flow

The bridge sits between two local processes:

```
Claude Desktop ──stdio──> Astro-Bridge ──HTTP 127.0.0.1──> Astro app
```

- **Stdio side**: receives JSON-RPC requests from Claude Desktop on stdin, writes responses to stdout. Standard MCP transport.
- **HTTP side**: forwards each request to the Astro app's MCP server, bound only to `127.0.0.1:8089` (loopback). The URL is fixed; there is no host discovery.

The bridge itself stores nothing of yours. All App Store Optimization data is stored by the Astro app locally on your machine. The bridge writes only a cached copy of the server's tool list to `~/Library/Caches/com.elarity.astro-bridge/tools.json` so the tool surface is available at launch.

## Data Collection

The bridge collects **no data**. Specifically:

- **No analytics or telemetry** are sent anywhere
- **No external network requests** are made — communication is loopback-only (`127.0.0.1`)
- **No data** is shared with third parties
- The only file the bridge writes is the tool-schema cache noted above

## Third-Party Sharing

No data is shared with any third party. The bridge has no remote network capability.

## Contact

For questions about this privacy policy, open an issue at:
https://github.com/apocryphx/Astro-Bridge/issues
