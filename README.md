# vez
Stop hunting through folders. Vez brings semantic intelligence to your local files.

Vez is an open-source, native macOS Spotlight replacement. It runs as a quiet
background agent and opens a focused file-search panel from anywhere on the Mac.

## Current development target

The first milestone provides:

- A native macOS 14+ agent application for Apple silicon
- No permanent Dock icon or conventional main window
- A centered search panel invoked with `Option-Space`
- Immediate keyboard focus and Escape-to-dismiss behavior
- A minimal menu-bar menu with Open Vez, Settings, and Quit

Indexing and search results will be added after the launcher interaction is
validated.

## Build locally

Requirements:

- macOS 14 or later
- Apple silicon Mac
- Xcode 15 or later

Open `Vez.xcodeproj` in Xcode and run the `Vez` scheme, or build from Terminal:

```sh
xcodebuild \
  -project Vez.xcodeproj \
  -scheme Vez \
  -configuration Debug \
  -derivedDataPath .build \
  build
```

The locally built application will be available under
`.build/Build/Products/Debug/Vez.app`.

Run the tests with:

```sh
xcodebuild \
  -project Vez.xcodeproj \
  -scheme Vez \
  -configuration Debug \
  -derivedDataPath .build \
  test
```

## License

Vez is licensed under the Apache License 2.0.
