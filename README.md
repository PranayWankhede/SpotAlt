# SpotAlt
Stop hunting through folders. SpotAlt brings semantic intelligence to your local files.

SpotAlt is an open-source, native macOS Spotlight replacement. It runs as a quiet
background agent and opens a focused file-search panel from anywhere on the Mac.

## Current development target

The current milestone provides:

- A native macOS 14+ agent application for Apple silicon
- No permanent Dock icon or conventional main window
- A centered search panel invoked with `Option-Space`
- Immediate keyboard focus and Escape-to-dismiss behavior
- A minimal menu-bar menu with Open SpotAlt, Settings, and Quit
- An index manager for enrolling one or more folders through the native macOS
  folder picker
- Persisted, read-only folder access using security-scoped bookmarks
- Background recursive filename and path indexing with common build noise
  excluded
- A central SQLite index stored under SpotAlt's Application Support directory;
  enrolled folders remain read-only and contain no SpotAlt-generated files
- Recursive FSEvents monitoring that incrementally adds, updates, moves, and
  removes SQLite records as enrolled folders change
- Fuzzy filename results with arrow-key navigation and Return-to-open behavior

SpotAlt performs an initial consistency scan when it launches or when search
locations change, then keeps the index current from filesystem events. File-content
search is planned for a later milestone.

## Build locally

Requirements:

- macOS 14 or later
- Apple silicon Mac
- Xcode 15 or later

Open `SpotAlt.xcodeproj` in Xcode and run the `SpotAlt` scheme, or build from Terminal:

```sh
xcodebuild \
  -project SpotAlt.xcodeproj \
  -scheme SpotAlt \
  -configuration Debug \
  -derivedDataPath .build \
  build
```

The locally built application will be available under
`.build/Build/Products/Debug/SpotAlt.app`.

Run the tests with:

```sh
xcodebuild \
  -project SpotAlt.xcodeproj \
  -scheme SpotAlt \
  -configuration Debug \
  -derivedDataPath .build \
  test
```

## License

SpotAlt is licensed under the Apache License 2.0.
