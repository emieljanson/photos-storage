# Cloud storage expansion

Investigation: 15 November 2026. The new iCloud Downloads implementation was
tested on an Apple silicon Mac running macOS 27.2. It compiles for macOS 13;
the new feature has not been runtime-tested on older systems.

## Result

**iCloud Drive is the first supported expansion in this development branch.**
Options → iCloud Drive → Manage Downloads opens a small native window. Choose
individual documents, review their upload status, then remove eligible local
downloads. Opening a document downloads it again. This is a manual action,
not an automatic storage target. It does not change the existing Photos target.

The public 0.4.1 download does not include this new feature yet.

## Capability assessment

| Category | Local-only removal | What was verified | Implementation decision |
| --- | --- | --- | --- |
| Photos | Existing native Photos cache service | Existing safety and runtime regression tests still pass | Keep the existing optimization behavior |
| iCloud Drive, including synced Desktop/Documents and individual iWork documents | Official `FileManager.evictUbiquitousItem(at:)` | Real upload, eviction to a cloud-only placeholder, redownload and SHA-256 comparison; native UI and signed app worker tested | Implement manual selection of uploaded, regular files |
| Messages / iMessage | Private native purge routes exist; no independently verified per-attachment round trip | A real attachment is not a ubiquitous file. Read-only CacheDelete reported 126,976 eligible bytes; ordinary Messages deletion propagates to other devices | Block cleanup; do not enable hidden purge switches, unlink attachments or edit the database |
| Mail / iCloud Mail | Native cache services and attachment download preferences exist, without a verified per-message round trip | A real Mail attachment is not a ubiquitous file. Account automation timed out even with permission; native estimates did not establish eligible content. Apple's Remove Attachments also deletes IMAP server copies | Block cleanup and automatic preference changes; see the Mail investigation below |
| Music | Remove Download exists in Music | Official UI semantics and local scripting dictionary inspected; `download` and library `delete` are exposed, a corresponding download-removal command is not | Manual native-app action only; no automated implementation or personal-track experiments |
| TV | Remove Download exists in TV | Official UI semantics and local scripting dictionary inspected; home videos can be local-only | Manual native-app action only; not runtime-tested |
| Books / audiobooks | Remove Download exists in Books | Apple documents redownloading purchases; imported files need separate cloud verification | Manual native-app action only; not runtime-tested |
| Podcasts | Remove Download and retention settings exist | Apple documents local downloads and automatic-download controls | Useful native controls, but a feed is not a permanent iCloud copy of an episode; not runtime-tested |
| Notes, Voice Memos, Contacts, Calendar, Reminders | No verified third-party per-item eviction route established | These are application-managed sync stores, not ordinary iCloud Drive documents | Do not remove local databases or their attachments |
| Safari offline content | Not established as an independently recoverable iCloud copy | A synced Reading List entry does not prove the full offline page is backed up | Outside the implemented feature |
| WhatsApp Desktop | Not established | An iPhone iCloud backup is not proof that a particular Desktop attachment can be restored | Outside the implemented feature; do not delete application data |
| Dropbox, OneDrive, Google Drive | Provider-specific online-only features | No connected-provider round trips performed | Separate providers, not iCloud; require their own verification |
| Local device backups, developer data and ordinary caches | Different semantics | Not iCloud document downloads | Outside this expansion; no Linear databases or project folders touched |

“Not established” means this investigation did not find and verify a safe route.
It is not a claim that a future macOS API or a more extensive investigation
could never support the category. A cloud-sync toggle or record identifier alone
does not prove that a particular local file has a restorable current cloud copy.

## Safety contract

- Only files explicitly chosen in the native file picker are considered.
- No recursive folder cleanup, automatic eviction, new background scan, or
  automatic changes to offline pinning are introduced.
- Require a regular file, positive allocated local size, confirmed iCloud
  membership, completed upload, current local version, no active transfers,
  no unresolved conflicts, no excluded-from-sync flag and no transfer errors.
- Unknown state blocks the action. Existing cloud-only placeholders need no work.
- Reject symbolic links, linked files and files inside app packages. Photo and
  media libraries and sparse disk images are explicitly excluded too.
- Re-read cloud state and check device/inode, size, modification time and change
  time against the reviewed selection immediately before requesting eviction.
  A changed file requires another review.
- The native API accepts a path. The final identity check cannot atomically
  prevent another process from replacing that path; concurrent replacement
  during the native request has not been validated.
- The only removal operation is Apple's `evictUbiquitousItem(at:)`. No file
  deletion or Photos/Messages/Mail item deletion is used by this feature.
- Each file runs in a separate worker invocation of the signed app. The worker
  has a 30-second watchdog and the parent has a 35-second deadline with forced
  termination if necessary. Closing the window cancels remaining files, not an
  already-issued native request.
- Report a reduction only after uploaded cloud-only status and zero local
  allocated bytes are confirmed. Counts describe local file allocations, not a
  guarantee that the whole disk's free-space counter increases immediately:
  snapshots or another app downloading the file can affect that counter.

The upload status is Apple's synchronization signal, not an independent cloud
backup audit. Offline files, recent edits, shared-file access and cloud failures
remain subject to the system provider. The app never retries a release in a
download/evict loop. There is no automatic iCloud Drive quota or claim that
Keep Downloaded can be reliably overridden or tracked through this interface.

## Verification

Only newly generated test documents were evicted. No personal Photos assets,
messages, mail, libraries, database contents or existing cloud archives were
removed.

- Initial characterization: a generated 4 MiB file completed three upload →
  eviction → download cycles. Every cloud-only observation reported zero local
  allocation and every restored file matched the original SHA-256.
- Production implementation: three more cycles using `inspectCloudFile` and
  `releaseCloudDownload`, with the same cloud-only observations and hash checks.
  An incorrect reviewed identity was refused in each cycle. A later unsynced
  edit was preserved when the old identity was submitted.
- Native UI: reviewed an uploaded test file alongside an intentionally local-only
  `.nosync` fixture. Remove Downloads released only the uploaded file; the
  unuploaded fixture remained. Redownload restored the original 4 MiB prefix
  and the exact later edit. The local-only fixture was unchanged.
- Signed app: tested the actual app's `--cloud-file` worker entry point,
  including confirmed eviction, allocated-size accounting and verified restore.
- Isolated tests cover uncertain and unsafe metadata, ordinary local files,
  symlinks in file and parent paths, library/package contents, changed selections,
  command validation, malformed/failed workers, inherited output descriptors,
  and an unresponsive worker that ignores normal termination.
- A model regression test reproduces cancellation before an inspection starts.
  Unchecked rows stop showing progress and remain ineligible for removal.
- Existing Photos, setup, helper-failure and control-protocol tests pass. The
  app, embedded helper and Settings pane still have macOS 13 deployment targets.

These are small-file, single-account tests on macOS 27.2. They do not validate
long-term automatic quotas, all cloud accounts, shared document permissions,
every file format, offline restoration or the new feature on older macOS versions.

## Reproduce without personal data

Run isolated checks with `zsh tests/run.sh`, then `zsh build.sh`. A Developer ID
signature is needed to launch a hardened app linked to Sparkle; see
[Development](DEVELOPMENT.md). Build outputs stay outside iCloud.

For a real cloud round trip, compile `tools/cloud-storage-probe.swift` together
with `Sources/Agent/CloudDownloads.swift`. Its `round-trip ICLOUD_FOLDER` command
creates a uniquely named Photos Storage Test folder and its own random 4 MiB
document. It never selects an existing document for eviction. The test leaves
its generated file available for inspection; remove that test folder afterwards.

`tools/preview-cloud-downloads.swift`, compiled with both CloudDownloads Swift
files and AppKit/SwiftUI into a separate app bundle, exercises the real window
and worker code without launching the Photos agent. Use generated fixtures only.

## Sources

- [Apple: evictUbiquitousItem(at:)](https://developer.apple.com/documentation/foundation/filemanager/evictubiquitousitem(at:)) — removes the local copy without removing the iCloud item.
- [Apple: Reducing your app's disk usage](https://developer.apple.com/documentation/xcode/reducing-your-app-s-disk-usage) — check upload status and evict local documents; deletion has different semantics.
- [Apple: Work with folders and files in iCloud Drive](https://support.apple.com/en-gb/guide/mac-help/mchl1a02d711/mac) — Remove Download and Keep Downloaded.
- [Apple: Delete messages and conversations](https://support.apple.com/guide/messages/delete-messages-and-conversations-icht1035/mac) — deletions propagate when Messages in iCloud is enabled.
- [Apple: Keep your messages up to date with iCloud](https://support.apple.com/en-vn/guide/icloud/mma17ed475f7/icloud) — automatic local/cloud storage management, without a selectable byte target.
- [Apple: Mail attachments](https://support.apple.com/en-ca/guide/mail/mlhlp1123/mac) — removing IMAP attachments also removes the server copy.
- [Apple: Mail Account Information](https://support.apple.com/en-al/guide/mail/cpmlprefacctinfo/mac) — All, Recent and None attachment download preferences, including their media exception.
- [Apple: Remove music downloads](https://support.apple.com/en-ie/102344) — distinguishes Remove Download from Delete from Library.
- [Apple: Manage the TV library](https://support.apple.com/guide/tvapp/manage-your-library-atvb2030c6e3/web).
- [Apple: Remove books](https://support.apple.com/en-mz/guide/books/ibks67184a3a/mac).
- [Apple: Podcasts downloads](https://support.apple.com/en-lamr/guide/podcasts/poda4f6be01/mac).
- [Apple: Delete and recover notes](https://support.apple.com/en-ie/guide/icloud/mm2f42f05cb9/icloud).
- [Apple: iCloud storage and Voice Memos](https://support.apple.com/en-gb/108922).

Community reports illustrate the demand, not the safety of suggested fixes:
[iCloud Drive Remove Download failure](https://discussions.apple.com/thread/255159616),
[large local Photos libraries](https://discussions.apple.com/thread/7232959), and
[large Messages history on smaller devices](https://discussions.apple.com/thread/254336204).
No user-suggested cache/database deletion workaround was used.

## Private native cache investigation

`tools/cloud-cache-services.m` resolves only the read-only itemized-estimate
function; it never resolves or calls a purge function. On this machine it found
services beyond the entries in `/System/Library/CacheDelete`:

- `com.apple.imagent.cache-delete_fspurgeable`: 126,976 bytes.
- `com.apple.PODCAST`: 1,105,920,000 bytes.
- Mail, Music, TV and Books services: zero eligible bytes at the time of testing.

These are estimates, can overlap other filesystem estimates, and are not an
inventory of restorable cloud originals. They must not be summed into a promised
disk-space saving or treated as a quota enforcement mechanism.

Read-only inspection of the installed `imagent` binary also found
`cacheDeleteEnabled`, `purgeAttachments:`, `purgeAttachmentsForChatGUID:` and
`purgeFileTransferFromDisk:reply:`, plus an internal `EnableCacheDelete` switch.
That establishes a potential research path, not a supported application contract.
The switch was not changed and no Messages purge was called. The investigation
did not establish its current-version upload checks, eligibility criteria,
third-party authorization, or an isolated attachment restore. The small native
estimate does not make the remaining Messages attachment store safely removable.

## Mail investigation

Mail was tested separately from Messages. Read-only filesystem accounting on
the test Mac found approximately 13.1 GB in the Mail store: 9.6 GB of message
bodies, 2.6 GB of attachments and 0.9 GB of indexes and other files. The separate
Mail Downloads folder accounted for approximately 117 MB. These are allocated
bytes, not an estimate of safely removable content.

The Mail index contains both IMAP and local-only mailboxes. Local mail and
restored messages cannot be assumed to exist on a server. No message bodies or
subjects were queried, and none of these files were changed or removed.

### Download preferences are not a storage target

Mail's Account Information screen offers All, Recent and None for Download
Attachments. Apple's current documentation says Recent covers 15 months and
that media attachments, including images, PDFs, video and audio, always download.
The preference governs other attachment types. None is therefore neither a GB
limit nor a promise to remove existing media. The native controls were inspected;
their values were not changed.

Mail's installed scripting dictionary exposes an older `messageCaching` property.
A separately signed test app requested account settings through ScriptingBridge,
with the user's Mail automation permission enabled. Account retrieval repeatedly
returned Apple event timeout -1712. Batched retrieval, an isolated main-thread
worker and one normal Mail restart did not resolve it. Rebuilding the app and
refreshing the same permission also did not establish reliable access. The
preference setter was never reached. This is a failed test on this machine,
not proof that every Mail version or account behaves the same way.

### Private cache services are not enough evidence

The installed Mail components contain `MailCacheDelete` and
`MFCacheDeleteAttachmentPurger`. Read-only inspection established that the latter
has separate estimate and purge entry points. A diagnostic using the observed
initializer found zero active and inactive accounts, although the native Mail
settings showed configured accounts. Its zero-byte result was consequently
invalid; `tools/mail-storage-probe.m` reports `mail_accounts_unverified` instead
of treating an empty account list as proof of zero eligible bytes. The separate
system CacheDelete estimates also returned zero, without a restore test.

No purge method was called, no account download preference was modified, and no
mail or attachment was deleted. There is no successful server redownload/hash
test for Mail, so this branch does not offer Mail cleanup or a Mail quota. The
failed automation prototype is not included in the production app.
