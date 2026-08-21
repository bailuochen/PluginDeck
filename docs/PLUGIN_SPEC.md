# Plugin Manifest Specification

Schema version 1 describes a PluginDeck plugin package. A package contains `plugin.json`, its executable entry point, and optional declarative UI resources.

## Example

```json
{
  "schemaVersion": 1,
  "id": "dev.example.tool",
  "name": "Example Tool",
  "summary": "A short, user-facing description.",
  "description": "A complete explanation of the plugin.",
  "version": "1.0.0",
  "category": "system",
  "author": {
    "name": "Example Developer",
    "url": "https://github.com/example"
  },
  "trustLevel": "community",
  "releaseStatus": "available",
  "permissions": ["shell", "file.read"],
  "networkDomains": ["api.example.com"],
  "compatibility": {
    "minimumHostVersion": "0.1.0",
    "minimumMacOSVersion": "13.0",
    "architectures": ["arm64", "x86_64"]
  },
  "entryPoint": {
    "executable": "bin/example-plugin",
    "protocolVersion": 1
  },
  "distribution": {
    "downloadURL": "https://github.com/example/tool/releases/download/v1.0.0/tool.zip",
    "updateURL": "https://raw.githubusercontent.com/example/tool/main/plugin.json",
    "sha256": "<64 lowercase hexadecimal characters>"
  },
  "repositoryURL": "https://github.com/example/tool",
  "icon": "wrench.and.screwdriver",
  "featured": false,
  "capabilities": ["Inspect environment", "Run a repair"],
  "actions": [{
    "id": "inspect",
    "title": "Inspect environment",
    "description": "Read the current tool configuration.",
    "icon": "stethoscope",
    "method": "environment.inspect",
    "requiresConfirmation": false
  }]
}
```

## Identity and compatibility

- `id` is immutable and uses reverse-DNS notation.
- `version` uses semantic versioning.
- `minimumHostVersion` declares the oldest compatible PluginDeck release.
- `architectures` contains `arm64`, `x86_64`, or both.
- `entryPoint.executable` must be a relative path inside the package.
- `actions` declares the commands rendered by the host. Version 1 external plugins must declare at least one action.

## Permissions

Version 1 defines `network`, `shell`, `file.read`, `file.write`, and `process.read`. Network access is further restricted by `networkDomains`. A plugin update that expands either list requires renewed user approval.

The `shell` permission is high risk. User-facing actions must expose the command purpose, working directory, and arguments before execution. Plugins should prefer structured host capabilities when available.

## Distribution

Published packages use HTTPS URLs and must include a SHA-256 digest. Marketplace CI rejects mutable URLs, duplicate IDs, invalid schemas and missing compatibility metadata.

## Runtime protocol

For each action, PluginDeck starts a fresh plugin process, writes one JSON-RPC 2.0 request followed by a newline to standard input, and reads one response from standard output. Diagnostic logs belong on standard error.

Request parameters contain `pluginID`, `actionID`, and the plugin-owned `dataDirectory`. The response result has `title`, `message`, and optional `detail` strings. Processes have a 60 second timeout.

See `examples/hello-plugin` for an executable reference package. In Developer Center, choose “Import local plugin” and select that directory.

## Import and marketplace flow

- Local development: select a directory containing `plugin.json`.
- Public Git repository: enter an HTTPS clone URL whose repository root contains `plugin.json`.
- Marketplace: publish an immutable ZIP release, add its exact manifest and SHA-256 to `marketplace/catalog.json`, then open a pull request.

Local and Git imports are always treated as `community`; a repository cannot grant itself official or verified status.
