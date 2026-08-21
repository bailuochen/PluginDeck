# PluginDeck Architecture

## Goals

PluginDeck is a native macOS host for developer-tool plugins. The host owns trust, installation, lifecycle, permissions, navigation, task progress, logs, and recovery. Plugins own domain behavior.

## Process boundary

Third-party code is never loaded into the host process as a Swift bundle or dynamic library. Each executable plugin runs as a child process and exchanges newline-delimited JSON-RPC 2.0 messages over standard input and output.

The host must be able to terminate a plugin after a timeout or user cancellation. A malformed response fails the active request without crashing the host.

## Lifecycle

```text
discover -> inspect -> download -> verify -> stage -> install -> enable
                                                     |
                                                     v
uninstall <- disable <- rollback <- update <- invoke
```

Installation and update are transactional:

1. Download to a staging directory.
2. Verify catalog metadata, manifest, compatibility and SHA-256.
3. Expand without following unsafe paths outside staging.
4. Make the entry point executable.
5. Atomically move the staged version into the plugin directory.
6. Retain the previous version for one-step rollback.

Uninstall removes plugin code and cache by default. Plugin settings and external tool data require separate, explicit choices.

## Trust and permissions

Catalog entries distinguish official, verified community, and unverified community plugins. Open source alone is not treated as verification.

Static permissions are displayed before installation. Dynamic resources, such as a project folder, are selected at the moment of use. An update that adds permissions requires confirmation. Environment variables and secrets are not inherited unless the host explicitly grants them.

Version 1 executable plugins are not strongly sandboxed. They run in a separate process for host stability, but macOS still gives that process the current user's filesystem and process privileges. Manifest permissions are auditable declarations, not an enforcement boundary. PluginDeck therefore labels direct imports as community code, requires an explicit execution warning, strips inherited secret environment variables, and recommends source review. Strong capability enforcement requires a future sandboxed helper architecture.

## Migration note

The complete NVM plugin is currently compiled as a separate Swift module and mounted by the host so the product remains useful while the process protocol is being implemented. Its models, service, parsers, views and tests are isolated from the host application target. It will become the first standalone reference plugin package.
