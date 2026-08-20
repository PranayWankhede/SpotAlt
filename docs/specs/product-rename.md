# SpotAlt product rename

## Scope

The repository, Xcode project, targets, modules, application bundle, source and
test directories, UI copy, documentation, queue labels, and notification names
use the SpotAlt product name.

## Compatibility

The application retains the existing `com.vez.search` bundle identifier during
the rename. The identifier is not user-facing, and retaining it allows the
renamed application to keep its current macOS sandbox container, preferences,
and security-scoped folder bookmarks.

On first use of the renamed build, the filename index migrates from the legacy
`Application Support/Vez` directory to `Application Support/SpotAlt`. Existing
SQLite index data remains available without requiring users to enroll their
folders again.

Changing to a SpotAlt bundle identifier is deferred until a separately planned
migration can preserve sandboxed user data and code-signing continuity.
