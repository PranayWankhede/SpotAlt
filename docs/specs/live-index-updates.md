# Live index updates

## User outcome

After a folder is enrolled, SpotAlt keeps filename search synchronized with that
folder without requiring an application restart or a manual full rescan.

## Scope

- Watch every enrolled root recursively with macOS FSEvents.
- Add or update a SQLite record when a regular file is created or modified.
- Replace the old record when a file or directory is renamed or moved within an
  enrolled root.
- Delete records when files or directories are deleted or moved out of an
  enrolled root.
- Reconcile only the affected file or directory subtree during normal event
  processing.
- Reconcile the complete affected root when FSEvents reports dropped events or
  another condition that makes incremental history unreliable.
- Preserve the existing exclusions for hidden items, packages, symbolic links,
  and common build directories.
- Ignore SpotAlt's own Application Support index directory so SQLite writes cannot
  create an indexing loop when a parent folder is enrolled.

## Behavior

FSEvents batches changes with a short latency. SpotAlt processes each batch on its
background indexing queue and applies all corresponding SQLite deletes and
upserts in one transaction. Search remains available while changes are being
processed, and index observers receive the updated file count afterward.

Directory events are reconciled as subtrees because a single move or rename can
affect every descendant path. Multiple overlapping directory events in one
batch are collapsed to the smallest set of top-level affected subtrees.

## Failure and recovery

- A malformed, unreadable, hidden, packaged, or symbolic item is omitted without
  stopping the remaining batch.
- If an incremental SQLite mutation fails, the existing index remains usable.
- FSEvents history-loss flags trigger a consistency scan of the affected root.
- Adding or removing enrolled roots restarts the watcher and retains the existing
  launch/location-change consistency scan.

## Acceptance criteria

- A newly created regular file becomes searchable without restarting SpotAlt.
- Renaming or moving a file removes its old path and indexes its new path.
- Renaming or moving a directory updates all indexed descendant paths.
- Deleting a file or directory removes its records.
- Normal file changes do not trigger a full enrolled-root scan.
- Dropped FSEvents recover through a full affected-root reconciliation.
- Automated tests cover create, rename, move, delete, directory rename, and
  dropped-event recovery.
