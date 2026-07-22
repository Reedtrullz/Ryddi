# Ryddi Privacy

Ryddi is a local-first macOS disk-space manager. It has no analytics, telemetry, advertising SDK, account system, or remote analysis service.

## What Ryddi reads

Ryddi reads local filesystem metadata such as paths, file types, allocated sizes, modification dates, device and inode identity, and whether an item is a symbolic link. It runs local `du` scans for configured cleanup roots and user-chosen audit folders.

Deep Audit reads file contents only when two large files have the same name and size. It computes SHA-256 locally to rule out false duplicate matches. Hashes and contents are not saved or uploaded. Content-verified duplicates remain review-only and are not automatically selected for cleanup.

Ryddi checks standard local folders to detect provider-managed Dropbox, Google Drive, iCloud Drive, MEGA, and OneDrive locations. It does not sign into providers, call provider APIs, or prove remote upload completion.

Full Disk Access can improve scan coverage. Ryddi can detect that a known folder is unreadable, but it cannot grant Full Disk Access itself.

## What Ryddi writes

Ryddi stores only its custom scan-path list in app preferences.

Clean and eligible Deep Audit actions move explicitly selected, freshly revalidated items to Finder Trash. Nothing is preselected. Before acting, Ryddi checks that the item is still the same non-symbolic filesystem object, remains inside the reviewed root, has no open files detected by a bounded local `lsof` check, and retains an executable safety classification. If the open-file check cannot complete, cleanup fails closed.

The Control action for Xcode DerivedData is available only for the exact standard DerivedData folder while Xcode is closed, and moves that folder to Finder Trash. Other Control suggestions are guidance-only.

Offload creates a new, uniquely named copy inside a provider-managed local folder. It never deletes or moves the original and does not claim that the provider uploaded the copy. Failed partial copies created by Ryddi are removed.

Ryddi can copy a plain-text opportunity report to the macOS clipboard at your request. Review it before sharing because filenames and local context can be private.

## Network behavior

Scanning, classification, hashing, cleanup, and auditing are local. Ryddi opens its GitHub help page only when you choose Help. Provider software may upload a copy placed in its managed folder according to that provider's own settings and privacy terms.

## Recovery and limits

Finder Trash is recoverable until emptied, but moving an item to Trash does not immediately increase free space. Files can change after any scan; Ryddi therefore fails closed when identity or classification changes. Review-only findings are information, not cleanup authorization.
