# EmojiCatalog

A bundled Unicode emoji catalog with shared Swift models and a generator executable.
Requires the macOS Swift toolchain; no external dependencies.

Run from this directory:

```sh
# Download the pinned Unicode/CLDR datasets and regenerate the bundled resources.
swift run generate-emoji-catalog

# Verify the resources are up to date without changing them (requires network access).
swift run generate-emoji-catalog --check

# Run library and generator tests offline.
swift test
```

Output is written to `Sources/EmojiCatalog/Resources/Emoji/`.
To update dataset versions, change the constants at the top of `Sources/EmojiCatalogGenerator/main.swift` and rerun the script.
