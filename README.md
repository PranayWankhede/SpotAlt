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

## Install from source

SpotAlt currently targets technical users and does not publish a signed binary.
Install it locally from source instead.

Requirements:

- macOS 14 or later
- Apple silicon Mac
- Git
- The full version of Xcode 15 or later, opened once to complete its setup

Clone the repository and run the installer:

```sh
git clone https://github.com/PranayWankhede/SpotAlt.git
cd SpotAlt
./scripts/install.sh
```

The script builds SpotAlt in Release mode, verifies the app bundle, installs it
at `~/Applications/SpotAlt.app`, and launches it. It can also safely replace an
existing installation without removing the SQLite index or enrolled-folder
permissions.

Open **Index Manager** from the menu-bar item and enroll the folders you want to
search. After indexing begins, press `Option-Space` from any application to open
SpotAlt.

### Update

Pull the newest source and run the same installer again:

```sh
git pull --ff-only
./scripts/install.sh
```

### Uninstall

Remove the application while preserving its index and settings:

```sh
./scripts/uninstall.sh
```

To also remove the index, settings, and enrolled-folder permissions:

```sh
./scripts/uninstall.sh --purge-data
```

The uninstall script moves removed items to the Trash so they remain recoverable.

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
