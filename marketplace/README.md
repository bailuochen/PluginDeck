# PluginDeck Marketplace Catalog

The public marketplace is loaded from `marketplace/catalog.json` on the `main` branch.

To submit a plugin:

1. Publish the plugin source in a public repository.
2. Create a ZIP whose root contains `plugin.json` and the declared executable.
3. Attach the ZIP to an immutable GitHub Release.
4. Generate its digest with `shasum -a 256 plugin.zip`.
5. Add the exact packaged manifest to `catalog.json`, including the HTTPS release URL and lowercase SHA-256.
6. Open a pull request with a link to the source and release.

Marketplace maintainers review permissions, compatibility, source provenance and package integrity. A listing does not make community code equivalent to an official PluginDeck plugin.
