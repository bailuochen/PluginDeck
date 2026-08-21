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
  "capabilities": ["Inspect environment", "Run a repair"]
}
```

## Identity and compatibility

- `id` is immutable and uses reverse-DNS notation.
- `version` uses semantic versioning.
- `minimumHostVersion` declares the oldest compatible PluginDeck release.
- `architectures` contains `arm64`, `x86_64`, or both.
- `entryPoint.executable` must be a relative path inside the package.

## Permissions

Version 1 defines `network`, `shell`, `file.read`, `file.write`, and `process.read`. Network access is further restricted by `networkDomains`. A plugin update that expands either list requires renewed user approval.

The `shell` permission is high risk. User-facing actions must expose the command purpose, working directory, and arguments before execution. Plugins should prefer structured host capabilities when available.

## Distribution

Published packages use HTTPS URLs and must include a SHA-256 digest. Marketplace CI rejects mutable URLs, duplicate IDs, invalid schemas and missing compatibility metadata.
