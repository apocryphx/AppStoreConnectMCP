# Astro Bridge

A native macOS MCP bridge that connects Claude Desktop to the **Astro** app — a local App Store Optimization (ASO) tool. Astro exposes an MCP server on `http://127.0.0.1:8089/mcp`; this bridge is the stdio↔HTTP adapter that lets Claude Desktop reach it.

## What this is

Astro tracks keyword rankings, ratings, and competitors for App Store apps. Claude Desktop speaks MCP over stdio to local subprocesses, while Astro's MCP server speaks MCP over HTTP. This bridge sits between them: it reads JSON-RPC from stdin, forwards each request to Astro's HTTP endpoint, and writes the response back to stdout.

```
Claude Desktop ──stdio──> Astro-Bridge ──HTTP──> Astro app
   (MCP client)            (stdio↔HTTP proxy)     (MCP server on
                                                   127.0.0.1:8089)
```

The bridge does no storage of its own beyond a tool-schema cache. All ASO data lives in the Astro app. The bridge is a thin, stateless pass-through — every request except `tools/list` is forwarded to Astro unchanged.

## Requirements

- macOS 14 or later (Apple Silicon or Intel)
- The **Astro** app installed and running locally (the bridge cannot work without it)
- Astro's MCP server **enabled**: Astro → Settings → MCP Server → turn on **Enable MCP Server**
- The server port left at the **default `8089`** — this bridge targets `127.0.0.1:8089` and does not read a custom port
- Claude Desktop

> **Why an `.mcpb` instead of a connector?** Astro's own docs describe connecting Claude Desktop via a Cloudflare HTTPS tunnel added as a *custom connector* — that path exists because Claude Desktop's remote-connector feature requires an HTTPS URL. This bridge takes the local route instead: a native stdio `.mcpb` that talks to Astro over loopback directly. No tunnel, nothing exposed to the internet, no HTTPS. Same server, simpler and more private for local use.

## Install

### Option 1: Download the `.mcpb` bundle

1. Download [`Astro-Bridge.mcpb`](https://github.com/apocryphx/Astro-Bridge/releases/latest/download/Astro-Bridge.mcpb)
2. Open Claude Desktop → Settings
3. Drag the `.mcpb` onto **Drag .MCPB or .DXT files here to install**
4. Make sure the Astro app is running

### Option 2: Build from source

Requires Xcode and Node (for `npx @anthropic-ai/mcpb pack`).

```bash
git clone https://github.com/apocryphx/Astro-Bridge.git
cd Astro-Bridge
xcodebuild -project Astro-Bridge.xcodeproj -scheme Astro-Bridge -configuration Release build
```

The build's "Package MCPB" run-script phase produces `Astro-Bridge.mcpb` at the project root. `scripts/package-mcpb.sh` does the same end-to-end with a clean isolated derived-data path (suitable for release). `scripts/smoke-test.sh` verifies the handshake, `tools/list`, a live `tools/call`, and bundled-bootstrap presence against a Debug build.

## How it works

Claude Desktop launches the bridge from the unpacked `.mcpb` and speaks JSON-RPC to it over stdio. The bridge is an `NSApplication` accessory (`LSUIElement=true`) — no Dock icon, no menubar item — with a stdio MCP server running on the main runloop. The AppKit lifecycle is in place so a future preferences window or status item can attach without re-architecting; today it has no UI.

Requests are handled two ways:

1. **`tools/list`** — answered locally from `SchemaCache`. On each call the bridge fetches `tools/list` live from Astro and persists it to `~/Library/Caches/com.elarity.astro-bridge/tools.json` as last-known-good. When Astro is down, the bridge serves that disk cache, falling back to a bootstrap JSON (`tools-bootstrap.json`) shipped inside the `.app` bundle for the very first launch with no cache yet. So Claude always sees the tool list, host up or down.

2. **Everything else** (`initialize`, `tools/call`, notifications, …) — forwarded transparently to Astro at `http://127.0.0.1:8089/mcp`.

Forwards are serialized: one request in flight at a time, in arrival order. MCP over stdio is request/response, and Astro's HTTP server is session-based and order-sensitive — it expects `initialize` to establish the session before any tool call. Serializing guarantees that ordering.

The bridge writes one file: the schema cache. That path is TCC-unrestricted, so no privacy prompts. No config files, no host discovery, no shared state with Astro.

### When Astro isn't running

The bridge doesn't fail silently. If the HTTP forward fails (host not running, or went down mid-session), the bridge enters degraded mode:

- `initialize` returns a stub with `serverInfo.name: "Astro (offline)"` and an `instructions` field telling the user to launch the app.
- `tools/list` is unaffected — it's always served from the bridge's cached schema (disk cache, falling back to the bundled bootstrap), host up or down.
- Other `tools/call` returns `isError: true` with a tool-specific message: _"Astro is not running. Launch Astro.app from /Applications to use '<tool>', then ask Claude to retry."_

On every subsequent request the bridge attempts the forward again, so the moment Astro comes up the bridge auto-recovers.

## Project structure

```
Astro-Bridge/
├── Astro-Bridge/
│   ├── main.m                          # NSApplication entry, sets up AppDelegate
│   ├── AppDelegate.{h,m}               # lifecycle; starts MCPServer
│   ├── MCPServer.{h,m}                 # serial STDIO loop, dispatch, EOF drain
│   ├── SchemaCache.{h,m}               # live tools/list proxy + disk + bootstrap fallback
│   ├── Forwarder.{h,m}                 # HTTP forward (sync + async), reachability state
│   ├── MCPFraming.{h,m}                # JSON-RPC 2.0 framing helpers
│   ├── DegradedResponses.{h,m}         # host-offline fallback responses
│   ├── AstroBridge.entitlements        # app-sandbox = false (required for STDIO)
│   ├── Resources/
│   │   └── tools-bootstrap.json        # cold-start schema fallback (server-derived)
│   └── Info.plist                      # LSUIElement=true, NSPrincipalClass=NSApplication
├── Astro-Bridge.xcodeproj/             # Xcode project (filesystem-synchronized group)
├── bundle/
│   ├── manifest.json                   # MCPB manifest (v0.3, bundle version 1.0.0)
│   ├── icon.png                        # extension icon
│   └── server/                         # .app staged here by build phase (gitignored)
├── scripts/
│   ├── extract-bootstrap-tools.sh      # regenerate Resources/tools-bootstrap.json
│   ├── smoke-test.sh                   # handshake / tools/list / tools/call / bootstrap
│   └── package-mcpb.sh                 # clean Release → .mcpb
└── Astro-Bridge.mcpb                   # packaged bundle (built automatically)
```

## Privacy

The bridge makes no network requests beyond `127.0.0.1`. Nothing leaves your machine. See [PRIVACY.md](PRIVACY.md).

## License

MIT — see [LICENSE](LICENSE).
