# SpotAlt v0.1 MVP

## Product promise

SpotAlt is a private Spotlight replacement that helps people find local documents
by meaning rather than filename. It lives quietly in the background, appears as
a search overlay from anywhere on the Mac, indexes only locations the user
approves, processes their content locally, and never modifies their files.

## Target user and platform

The first user is a macOS knowledge worker with a large, poorly organised
collection of receipts, notes, PDFs, and project documents. The initial target
is Apple silicon Macs running macOS 14 or later. Cross-platform support is not
part of v0.1, but the search and indexing design should not unnecessarily
prevent it later.

## Product form

SpotAlt is not experienced as a conventional desktop application. It is a macOS
agent utility with no primary window and no permanent Dock icon. It starts at
login after the user approves that behavior, maintains the local index in the
background, and presents a centered search panel only when invoked. An optional
menu-bar item provides indexing status, Settings, pause/resume, and Quit.

SpotAlt is a native `SpotAlt.app`. During the technical preview it is built and
installed from source with the repository's one-command installer. A signed and
notarized DMG remains an option if the project later targets non-technical users.
The bundle contains the search engine, indexer, extractors, database support, and
interface resources; it requires no Python, Docker, or separately installed
service at runtime.

## Core job

When a user remembers what a file is about but not its name or location, they
can search in everyday language and open the correct file within seconds.

Example: `flight receipt from Lisbon` finds `invoice-2024-09.pdf` because its
contents mention the airline and trip.

## v0.1 user flow

1. On first launch, SpotAlt explains its local-only, read-only model and recommends
   Desktop, Documents, and Downloads. The user explicitly approves each
   location, can remove recommendations, add another folder, or skip setup.
2. SpotAlt begins indexing in the background and shows progress without blocking
   search or normal Mac use.
3. Onboarding offers two shortcut modes:
   - **Replace Spotlight:** the user disables Spotlight's `Command-Space`
     shortcut in macOS Settings, then assigns `Command-Space` to SpotAlt.
   - **Keep Spotlight:** SpotAlt uses `Option-Space` by default.
   SpotAlt cannot silently change the macOS Spotlight shortcut. Both choices remain
   configurable later.
4. The user invokes SpotAlt from anywhere. A compact, centered search panel appears
   above the current app on the active display and immediately accepts input.
5. The user enters a filename, phrase, or natural-language description.
6. SpotAlt returns one ranked result per file with its name, path, type, modified
   date, and best matching-content snippet.
7. Arrow keys navigate results, Return opens the selected file, a secondary
   action reveals it in Finder, and Escape dismisses SpotAlt.
8. SpotAlt watches approved folders and updates the index when files are added,
   edited, moved, or deleted.

## Required capabilities

- Guided setup plus Settings for adding, removing, and viewing indexed folders.
- Persistent read-only folder access approved through macOS.
- Filename, full-text, and semantic search with file-level ranking.
- Text extraction from plain text, source code, searchable PDFs, Word and
  OpenDocument files, plus formats supported by macOS metadata importers.
- Automatic background indexing and filesystem change monitoring.
- A configurable global shortcut and keyboard-first search panel, including a
  guided path for using `Command-Space` as a Spotlight replacement.
- Open results in their default application or reveal them in Finder.
- Persist settings and the index across restarts.
- Local diagnostics for skipped or failed files.
- Background agent operation without a primary window or permanent Dock icon.
- Optional launch at login, enabled only with user consent.
- A menu-bar item for indexing status, pause/resume, Settings, and quitting SpotAlt.

## Search behavior

- Results represent files, not individual text chunks. Multiple matches from the
  same file are combined, using the strongest passage as the preview.
- Ranking considers filename, path, exact content matches, and semantic
  relevance. Exact filename matches should receive a strong boost.
- Search remains available during indexing and clearly indicates when results
  may be incomplete.
- Before the embedding model is ready, filename and full-text search still work.
- A no-results state suggests a shorter query and shows whether indexing is
  incomplete or the search scope is empty.

## Indexing boundaries

- SpotAlt recursively reads regular files inside approved folders.
- Hidden files and folders, application packages, archives, and system metadata
  are excluded by default. Supported document packages such as Pages and RTFD
  are indexed as single files without traversing their internal contents.
- Symbolic links are not followed in v0.1.
- Plain-text files larger than 5 MB and structured documents larger than 50 MB
  are skipped for content extraction but remain searchable by filename.
- Encrypted, unreadable, unsupported, and malformed files are skipped without
  stopping the rest of the index.
- Separate file paths remain separate results even when their contents match.
- Unavailable removable folders retain their index but are marked offline;
  results cannot be opened until the folder returns.

## Local model and privacy

- File contents, extracted text, search queries, and embeddings never leave the
  Mac. SpotAlt has no account, telemetry, or server-side processing in v0.1.
- The embedding model is downloaded only after the user consents. Setup shows
  its download size and progress; after download, search works offline.
- The exact model and packaged size will be selected in an early technical
  spike, prioritising search quality, memory use, and startup time.
- Removing an indexed folder immediately deletes its extracted text and
  embeddings from SpotAlt. Uninstall/reset guidance explains how to remove the
  entire local index.
- If access is revoked, SpotAlt stops reading the folder, marks it unavailable, and
  offers a clear action to restore access or remove its index.

## Launcher behavior

- SpotAlt runs as a macOS agent utility and does not appear permanently in the Dock
  or application switcher.
- The search panel is the primary interface. It appears on the active display
  and focuses the search field immediately, including over fullscreen apps and
  across macOS Spaces where permitted.
- SpotAlt detects shortcut registration failure and asks the user to resolve the
  conflict or record another shortcut.
- Choosing `Command-Space` never changes system settings automatically. SpotAlt
  guides the user to macOS Keyboard Settings and verifies the shortcut afterward.
- Closing or pressing Escape clears the current query and returns focus to the
  previously active app.
- Launch at login is offered but not enabled without consent.
- Settings and diagnostics are secondary utility panels reached from the menu
  bar or search panel; they do not turn SpotAlt into a conventional windowed app.
- Quitting SpotAlt stops background indexing and unregisters the active shortcut
  until SpotAlt is launched again.

## Empty and failure states

- With no approved folders, the launcher explains that there is nothing to
  search and offers `Add Folder`.
- Indexing progress shows files discovered, indexed, skipped, and failed.
- Model download or loading failures preserve filename and full-text search and
  provide a retry action.
- Permission loss, offline folders, and unsupported files are visible without
  presenting alarming or blocking errors.

## Deferred until after v0.1

- OCR for images and scanned PDFs.
- EPUB, audio, video, and embedded-media extraction.
- Typo-tolerant/fuzzy matching beyond normal full-text tokenisation.
- Advanced filters, saved searches, summaries, and chat with documents.
- Cloud drives, network drives, browser data, and whole-disk indexing.
- Editing, moving, renaming, deleting, or syncing user files.
- Accounts, sharing, telemetry, Windows, and Linux support.
- Searching applications, contacts, messages, web results, calculations, or
  other non-file categories provided by Apple's Spotlight.

## Success criteria

- A new user can approve a recommended folder and complete a first search
  without documentation.
- A user can choose either `Command-Space` replacement mode or the fallback
  shortcut during onboarding and invoke SpotAlt from another application.
- For a representative personal collection, common retrieval queries place a
  relevant file in the top five results.
- The launcher is visible and ready for input within 150 ms on the target Mac.
- Existing-index search returns initial results within 300 ms for an index of at
  least 25,000 files.
- Search and foreground applications remain responsive during indexing; SpotAlt
  reduces indexing work under battery or thermal pressure.
- Every approved folder can be removed along with its index, and all indexed
  content and embeddings remain local.

## First engineering milestone

Build the thinnest end-to-end Spotlight-replacement slice:

1. Launch a native macOS agent with no permanent Dock icon and show its search
   panel with a global shortcut.
2. Let the user approve one folder and persist read-only access.
3. Index filenames and contents from TXT, Markdown, and text-based PDF files.
4. Search the index by filename and full text, display one result per file, and
   open the selected result.
5. Add semantic ranking behind the same search interface and compare its quality
   against a small, repeatable set of example files and queries.
6. Package the slice as a self-contained `.app` that launches without developer
   tools or external services; production signing and notarization are required
   before public distribution.

The milestone is complete only when the full select-index-search-open loop works
locally. Visual polish, additional formats, OCR, and production-grade background
monitoring follow after this core risk is validated.
