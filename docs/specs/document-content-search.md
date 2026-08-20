# Document content search

## User outcome

SpotAlt finds a document when the query appears inside its text, even when the
filename does not contain the query. Each content match shows the strongest
matching excerpt and still opens the original file with Return.

## Supported extraction

- UTF-8, UTF-16, Latin-1, and Mac Roman plain text
- Markdown, CSV, JSON, XML, logs, configuration, and common source-code formats
- Searchable PDFs through PDFKit
- DOC, DOCX, RTF, RTFD, WordML, OpenDocument text, and web archives through AppKit
- Pages, Numbers, Keynote, PowerPoint, and Excel through the installed macOS
  metadata importers

Image-only and scanned PDFs require OCR and are intentionally deferred. Encrypted,
unreadable, malformed, oversized, and unsupported documents remain searchable by
filename but do not receive content chunks.

## Storage and ranking

SQLite schema version 2 adds file sizes, a content extraction version, and a
chunk-level FTS5 virtual table using the Unicode tokenizer with diacritic folding.
Queries are converted to escaped prefix terms before they reach FTS5, preventing
user input from being interpreted as raw FTS syntax.

Results remain file-based rather than chunk-based. FTS rows are deduplicated by
file, the best-ranked chunk supplies the excerpt, and filename matches receive a
strong ranking boost over content-only matches.

## Performance boundaries

- Plain text is capped at 5 MiB; structured documents and PDFs at 50 MiB.
- Extracted text is capped at 1,000,000 characters per file.
- Text is divided into at most 512 chunks of roughly 2,000 characters with a
  200-character overlap so phrases near boundaries remain searchable.
- Extraction runs serially on SpotAlt's utility queue, keeping interactive search
  and foreground applications responsive.
- SQLite writes are committed in batches of up to 64 files under WAL mode while
  searches use a separate read-only connection.
- Launch scans reconcile paths and metadata instead of replacing the database.
  Existing FTS chunks survive when modification date and size are unchanged.
- A changed fingerprint deletes stale chunks immediately; only the changed file
  is extracted again. FSEvents also removes chunks for moved or deleted files.

## Privacy

Extraction is local and read-only. SpotAlt does not upload file contents, queries,
or excerpts. The iWork and Office fallback invokes macOS's local metadata importer
in test mode and writes the returned attributes only to a temporary file inside
the application's sandbox before inserting text into SpotAlt's SQLite database.

## Acceptance criteria

- A phrase absent from a filename can find a text, PDF, Word, or Pages document.
- A result displays a matching excerpt and opens the original document.
- Editing content removes the stale match and adds the new match after FSEvents.
- Deleting or moving a file removes content rows associated with its old path.
- Restarting SpotAlt does not re-extract documents whose modification date and
  size have not changed.
- Search remains available while background extraction is running.
