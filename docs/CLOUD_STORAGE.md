# Cloud storage expansion

Investigation: 15 November 2026. The new iCloud Downloads implementation was
tested with a real iCloud account on an Apple silicon Mac running macOS 27.2.
The app compiles for macOS 13. The current Drive and Books extension passed
test/build and same-binary smoke checks on macOS 15, 26 and 27, plus a local
Developer ID signed build on macOS 27.2. Real cloud round trips
remain unverified on older systems.

## Result

**Mail and Messages are the priority; neither has a verified storage quota yet.**
The investigation found concrete gaps in their native cleanup behavior, described
below. A modeled IMAP window reclaimed and restored Mail files across two cycles.
A temporary real Gmail window reclaimed 1.64 GB and survived a Mail restart;
restoring Unlimited reset the native index, then restored all 117,821 All Mail rows.
A native Messages purge request was rejected for missing Apple entitlements.
A separate generated Drive-backed archive recovered media, with helper, cache
and recovery limitations described below.

**iCloud Drive and iCloud-synced Books downloads are supported in this branch.**
Options → iCloud Downloads → Manage Downloads opens a small native window.
Choose iCloud Drive or Books, review selected documents' upload status, then
remove eligible local downloads. Opening a document downloads it again. This
is a manual action, not an automatic storage target. It does not change the
existing Photos target.

The public 0.4.1 download does not include this new feature yet.

## Capability assessment

| Category | Local-only removal | What was verified | Implementation decision |
| --- | --- | --- | --- |
| Photos | Existing native Photos cache service | Existing safety and runtime regression tests still pass | Keep the existing optimization behavior |
| iCloud Drive regular files, including synced Desktop/Documents | Official `FileManager.evictUbiquitousItem(at:)` | Real upload, eviction to a cloud-only placeholder, redownload and SHA-256 comparison; native UI and signed app worker tested | Implement manual selection of uploaded regular files; package-format iWork documents remain excluded |
| Messages / iMessage | Native purge mechanisms exist; a separate managed Drive archive was tested | Native purge was rejected for missing entitlements. A generated archive recovered media; follow-up provider recovery kept the same mount and required refreshed collection metadata | Block native cleanup and personal migration; cold native movie recovery after an outage and cache quotas remain unproven |
| Mail / iCloud Mail | A Gmail message-count window can reduce the native mirror | A modeled IMAP window passed two cycles. A temporary real Gmail window reclaimed 1.64 GB, persisted across restart, and triggered native reset/backfill when reverted | No Mail quota or cleanup feature shipped; Gmail integration needs account-wide UX and Google's scope verification |
| Music | Native Remove Download client found; read-only connection works | Exact persistent-ID payload verified against Apple's storage extension. A real catalogue download test was blocked by Apple's associated-device limit | Do not enable removal without a successful download/removal/restore test |
| TV | Remove Download exists in TV | Official UI semantics and local scripting dictionary inspected; home videos can be local-only | Manual native-app action only; not runtime-tested |
| iCloud-synced Books PDFs and EPUB packages | Official iCloud eviction for uploaded document roots | Generated PDF restored byte-for-byte through Books; generated EPUB restored all seven package files with identical SHA-256 hashes | Implement selected PDFs and EPUB packages in the canonical Books iCloud documents folder; do not scan offloaded packages |
| Other Books purchases / audiobooks | Native download removal exists | Native BookKit client rejected an ordinary helper's entitlement; no purchase/audiobook restore test performed | Exclude items outside verified iCloud document storage |
| Podcasts | Remove Download and retention settings exist | Apple documents local downloads and automatic-download controls | Useful native controls, but a feed is not a permanent iCloud copy of an episode; not runtime-tested |
| Notes, Voice Memos, Contacts, Calendar, Reminders | No verified third-party per-item eviction route established | Native local-asset purge methods exist in Notes and Voice Memos, but a usable authorized per-item contract and restore were not established | Do not remove local databases or their attachments |
| Safari offline content | Not established as an independently recoverable iCloud copy | A synced Reading List entry does not prove the full offline page is backed up | Outside the implemented feature |
| WhatsApp Desktop | Not established | An iPhone iCloud backup is not proof that a particular Desktop attachment can be restored | Outside the implemented feature; do not delete application data |
| Dropbox, OneDrive, Google Drive | Provider-specific online-only features | No connected-provider round trips performed | Separate providers, not iCloud; require their own verification |
| Local device backups, developer data and ordinary caches | Different semantics | Not iCloud document downloads | Outside this expansion; no cleanup of personal databases or project folders |

“Not established” means this investigation did not find and verify a safe route.
It is not a claim that a future macOS API or a more extensive investigation
could never support the category. A cloud-sync toggle or record identifier alone
does not prove that a particular local file has a restorable current cloud copy.

## Why Mail and Messages

Independent reports describe the same requested outcome: keep history in the
cloud while reducing the Mac's local mirror. Examples include Messages using
[57 GB versus 1.6 GB on an iPhone](https://www.reddit.com/r/MacOS/comments/1jb3768/messages_taking_up_57gb_of_local_storage_with/)
and [54 GB versus less than 8 GB](https://www.reddit.com/r/MacOS/comments/1o423ay/messages_taking_up_54gb_mac_storage_but_icloud_is/),
plus Mail stores of [290 GB](https://www.reddit.com/r/macapps/comments/1kkg8w9/mail_app_in_macos_using_too_much_space/)
and [300 GB](https://www.reddit.com/r/macapps/comments/1fptz6j/why_cant_i_reduce_the_size_of_my_mac_mail_file/).
These are recurring individual reports, not prevalence measurements.

A [2026 Apple Developer Forums thread](https://developer.apple.com/forums/thread/837967)
also reports repeated Mail import-folder growth while Google accounts are
inactive. That is a distinct account/OS failure to diagnose, not evidence that
all large Mail stores are duplicate caches. Messages reset advice likewise
includes a [report of the full cache downloading again](https://www.reddit.com/r/MacOS/comments/1qbc14o/store_all_of_your_imessages_in_icloud_not_on_your/).
Neither reset instructions nor a cache directory name proves safe reclamation.

## iCloud Downloads safety contract

- Only files explicitly chosen in the native file picker are considered.
- No recursive folder cleanup, automatic eviction, new background scan, or
  automatic changes to offline pinning are introduced.
- Require a supported document, positive allocated local size, confirmed iCloud
  membership, completed upload, current local version, no active transfers,
  no unresolved conflicts, no excluded-from-sync flag and no transfer errors.
- Unknown state blocks the action. Existing cloud-only placeholders need no work.
- Reject symbolic links, linked files and files inside app packages. The sole
  package exception is an EPUB root directly inside the canonical Books iCloud
  documents folder. Photo/media libraries and sparse disk images stay excluded.
- Inspect an offloaded book using root cloud metadata and the filesystem's
  dataless flag. Never enumerate its contents to measure it: that can download
  the entire book again. Inspect internal metadata only for a materialized book.
- Re-read cloud state and check device/inode, size, modification time and change
  time against the reviewed selection immediately before requesting eviction.
  A changed file requires another review.
- Create a real Objective-C file-reference URL before the final eligibility and
  identity check, then retain that reference through native eviction. A controlled
  cloud test moved A and put B at its old path: only A was evicted and restored;
  B remained unchanged. Swift URL bridging does not preserve this reference.
  This is not a general atomicity guarantee against concurrent in-place writes.
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

Direct eviction and retained-file experiments targeted generated fixtures only.
Separately, an explicitly approved temporary Gmail setting let native Mail reduce
older personal local cache entries through normal synchronization. Investigation
code never deletes Mail files, edits its database or issues message-deletion
commands. Personal Photos assets, Messages attachments, libraries, existing cloud
archives and project data were preserved. A catalogue music download was
attempted for the native removal test; Apple blocked it before a local track was
created, so no music removal occurred.

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
- Books PDF: imported a generated 33,272-byte document, confirmed completed
  upload, evicted 36,864 allocated bytes to a cloud-only placeholder, then
  restored it through the native Books UI. SHA-256 matched the source.
- Books EPUB: imported a generated book package. Initial measurement incorrectly
  appeared to show no eviction because enumerating the package immediately
  materialized it again. A root-only check instead confirmed uploaded,
  not-downloaded status, `SF_DATALESS` and zero root blocks. Opening the item
  in Books restored all seven files with identical SHA-256 hashes.
- The signed production worker then released the EPUB's 61,440 allocated bytes.
  Three subsequent inspections left it cloud-only; an incorrect reviewed
  identity was refused. The native review window also released the generated
  PDF while leaving the already-offloaded EPUB alone. Both were restored through
  Books again, with the PDF and all seven EPUB files matching their original hashes.
- A PDF open in Preview was refused with native file-locking / `EBUSY` errors.
  Normally closing Preview allowed the same request to succeed. The app explains
  that an in-use file must be closed; it never forces the document closed.
- Existing Photos, setup, helper-failure and control-protocol tests pass. The
  app, embedded helper and Settings pane still have macOS 13 deployment targets.

These are small-file, single-account tests on macOS 27.2. They do not validate
long-term automatic quotas, all cloud accounts, shared document permissions,
every file format, offline restoration or the new feature on older macOS versions.

## Reproduce without personal data

Run isolated checks with `zsh tests/run.sh`, then `zsh build.sh`. A Developer ID
signature is needed to launch a hardened app linked to Sparkle; see
[Development](DEVELOPMENT.md). Build outputs stay outside iCloud by default;
`PHOTOS_STORAGE_BUILD_DIR` can override that location.

For a real cloud round trip, compile `tools/cloud-storage-probe.swift` together
with `Sources/Agent/CloudDownloads.swift` and the Objective-C handoff:

```sh
probe_build=$(mktemp -d /tmp/photos-storage-probe.XXXXXXXX)
xcrun clang -fobjc-arc -Wall -Wextra -Werror -c Sources/Shared/CloudEviction.m -o "$probe_build/CloudEviction.o"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
  -import-objc-header Sources/Shared/CloudEviction.h \
  Sources/Agent/CloudDownloads.swift tools/cloud-storage-probe.swift \
  "$probe_build/CloudEviction.o" -o "$probe_build/cloud-storage-probe"
```

Its `round-trip ICLOUD_FOLDER` command
creates a uniquely named Photos Storage Test folder and its own random 4 MiB
document. It never selects an existing document for eviction. The test leaves
its generated file available for inspection; remove that test folder afterwards.
It also creates its local-only fixture and a local verification manifest. Restore
verification rejects folders not registered by the generator before downloading.

`tools/preview-cloud-downloads.swift`, compiled with both CloudDownloads Swift
files and AppKit/SwiftUI into a separate app bundle, exercises the real window
and worker code without launching the Photos agent. Use generated fixtures only.
The preview needs the same imported header and linked Objective-C object.

## Sources

- [Apple: evictUbiquitousItem(at:)](https://developer.apple.com/documentation/foundation/filemanager/evictubiquitousitem(at:)) — removes the local copy without removing the iCloud item.
- [Apple: File-reference URLs](https://developer.apple.com/documentation/foundation/nsurl/filereferenceurl()) — track an item across moves and renames.
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
- [Apple: Associated devices for media purchases](https://support.apple.com/en-ie/118412) — the media association list is available through Music or TV; it differs from the general Apple Account device list.
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
- Mail, Music, TV and Books services: zero-byte estimates at the time of testing.

These are estimates, can overlap other filesystem estimates, and are not an
inventory of restorable cloud originals. They must not be summed into a promised
disk-space saving or treated as a quota enforcement mechanism. Mail's zero is
also subject to the metadata-discovery failures described below.

Read-only inspection found native Messages purge methods and cache-delete gates.
They are not a supported third-party application contract. The effective native
gate depends on account security, server policy and iCloud state; an absent
`EnableCacheDelete` preference does not mean cleanup is disabled. No gate was
bypassed. The small estimate does not establish
a restorable cloud copy of the remaining attachment store.

### Messages: deeper tests

The native `IMFileTransfer.canMarkPurgeable…` eligibility predicate was exercised
with 3,584 synthetic combinations, without instantiating personal transfers.
It requires synced/finished states and excludes audio, stickers, group photos
and most plugin payloads. Separate native date objects confirmed a 30-day
download window and a full-history mode. Active settings were not changed.
The real Messages-in-iCloud flag was enabled at the time of testing.

Further tracing found `AttachmentDownloadEarliestDate` in the user-owned
`com.apple.imagent` preference domain. It contains a sync-date anchor and a
timeframe. The active timeframe was already 1, but its anchor was approximately
32 days old: the effective initial-download cutoff was therefore about 62 days
before the test, not a rolling 30-day limit. Native synthetic tests confirmed
that choosing timeframe 1 again preserves that anchor.

The live daemon caches the earliest date in its own process. Calling the setter
in our app would update our app's defaults/cache; writing the daemon's preference
alone was not proven to refresh that cache. A change notification exists, but
a working external reload path was not established. No preference, notification
or daemon restart was used to claim a live retention feature. This mechanism
concerns future/backfill downloads, not verified removal of existing attachments.

A read-only request to the real Messages daemon returned Cocoa error 4097.
The daemon log for the exact test-process PID explicitly rejected missing
allowed entitlements. The active policy getter therefore did not work from
the ordinary helper.

The direct per-transfer purge wrapper was also inspected. It checks that the
path is inside Messages attachments, then removes the local file; that wrapper
does not itself establish a current cloud copy. Its existence does not justify
calling it on arbitrary local attachments.

The centralized CacheDelete broker is different. Read-only estimates with a
Messages-only service filter returned exactly that service; a nonexistent-service
negative control returned none. Urgencies 1–2 reported zero bytes, and 3–4
reported 126,976 bytes. Its filesystem-purge route accepts a service/type, volume
and byte budget, with no chosen attachment GUID or path selector found. It can
therefore select existing personal attachments before a generated test item.
No broker purge or user-managed-cache policy change was performed.

Native CloudKit record-fetch and validation machinery exists in another manager,
but this investigation did not establish that every broker purge freshly passes
through that validation. An open-source attachment manager was also examined:
its [removal code](https://raw.githubusercontent.com/svanvliet/imessage-attachment-app/main/Sources/Services/AttachmentFileManager.swift)
uses Trash, while its [selection query](https://raw.githubusercontent.com/svanvliet/imessage-attachment-app/main/Sources/Services/MessagesDatabase.swift)
does not verify cloud-upload state. It is not evidence of safe local eviction.

### Messages: companion assets and synchronization

Filename-only accounting initially left approximately 2.67 GB unmatched. Most
files instead matched a current/original transfer GUID or a known attachment
parent. About 2.55 GB of associated MOV files belonged to synced, waiting-for-accept
transfers whose main file appeared offloaded. The native Live Photo path helper
did not identify these MOV paths as Live Photo companions. They remain associated
alternate/family assets; neither a leak nor their individual cloud recoverability
was proven. They were preserved. Native finished-transfer eligibility alone misses
these families and must not be used as a complete disk-space inventory.

Before a manual sync, 709 finished-transfer records reported upload unsuccessful
and had no server token. They cannot be assumed backed up. The native iCloud
pane showed Download Attachments: 30 Days and Keep Messages: Forever. Sync Now
completed with Synced just now; those two settings were left unchanged. Transfer
state counts and the service-scoped estimates were unchanged afterward, including
the 709 unsuccessful records. The status does not prove those records or companion
files are safe to remove.

A generated 3-second Live Photo pair passed public `PHLivePhoto` validation;
a mismatched pair was rejected. Direct sharing of a `PHLivePhoto` object was
unavailable. The pair was instead imported as one Live Photo in Photos and,
with explicit permission, shared to the user's own iMessage account. The delivered
attachment contained both resources, with SHA-256 matching the generated sources.

Two reversible missing-cache tests retained the originals in quarantine and
independent backups. Opening the message did not restore a missing JPEG, nor
did it restore a missing pair. Save Photo then recovered both resources at a
new native transfer path, with new inodes and identical hashes. The transfer
changed from pending validation to synced. The logs did not identify an
attributable cloud-server fetch, so another native local cache remains a possible
source. This proves recovery of this fixture, not independent iCloud restoration.
It also shows why a cached thumbnail is insufficient evidence of an intact original.

Once the generated transfer was synced and finished, a guarded helper made one
real `purgeFileTransferFromDisk:reply:` request for that GUID. The daemon rejected
the exact helper PID for missing allowed entitlements; no reply or cache reduction
followed. Both recovered files and their metadata remained unchanged. No database
edit, forged Apple identity or direct-deletion fallback was used. A reliable
third-party Messages quota remains unproven.

### Messages: a generated Drive-backed archive

A separate test stored a verified extra copy of the generated JPEG/MOV pair in
iCloud Drive and served it through a read-only helper and macOS's WebDAV client.
Only the generated transfer temporarily used that mounted backing. This creates
an additional archive and depends on the helper, mount and Drive originals; it
does not verify or evict the native iMessage cloud copy. No Messages database
write or personal attachment migration was used.

With both Drive resources initially cloud-only, one pass fetched both through
the helper and native Quick Look displayed the full Live Photo with moving LIVE
playback. A later cold repeat fetched a fresh JPEG and showed moving LIVE, but
the MOV's Drive source remained cloud-only: cached motion was still possible.
Full cold JPEG/MOV recovery was demonstrated once, not repeatedly.

The initial mount used `-S`. Stopping the helper while LIVE was warm did not stop
playback. The temporary WebDAV mount then disappeared. A cold/reopened
unavailable state lacked Quick
Look, Copy and Share; the checked attachment identity and transfer/cloud state
remained unchanged, with no synchronized deletion observed. Restoring the
server and same mount, then opening a new conversation window, did not refresh
availability. A normal Messages quit/relaunch restored Quick Look and moving
LIVE without restarting imagent. Automatic provider recovery remains unproven.

An empty WebDAV cache directory did not mean its disk allocation was gone. One
unlinked JPEG still held by the client had 24,576 allocated bytes. A cross-process
file-descriptor scan was incomplete and did not cover memory mappings or
kernel-only references, so total retained cache allocation remains unknown.
This retained-original experiment establishes neither net disk savings nor a
cache quota. The original fixture files and their native companion package were
restored with their original inodes and matching SHA-256 hashes. Native Quick
Look then played the moving Live Photo with the test server and mount stopped.
Personal migration is not enabled.

A follow-up server-outage test omitted `mount_webdav -S`, which explicitly
unmounts an unresponsive server. The same mount and Apple client survived, but
file lookups initially returned cached `ENOENT` despite a fresh directory listing.
This matches [Apple's negative-lookup cache logic](https://github.com/apple-oss-distributions/webdavfs/blob/main/webdav_fs.kextproj/webdav_fs.kmodproj/webdav_vnops.c#L1045):
failed lookups can be cached, and a changed parent modification time clears them.
Changing only the synthetic root collection's modification time restored lookups
after about 35 seconds in this run, without changing file data or versions.

Reopening Quick Look then displayed moving LIVE without remounting or restarting
Messages or its daemon. Only the JPEG was freshly fetched; the movie remained
cloud-only, so cached motion was still possible. A subsequent explicit test-helper
read fetched the complete cloud-only movie through the same mount with matching
SHA-256. That reader previously failed with `ENOENT` before the metadata fix.
This separates verified transport recovery from native cold-movie recovery.
Apple's [separate metadata cache timeouts](https://github.com/apple-oss-distributions/webdavfs/blob/main/mount.tproj/webdav_cache.h#L135)
also mean recovery need not be immediate. All fixture originals were restored
again and moving LIVE verified with the temporary server and mount removed.

## Mail investigation

The test Mac held approximately 13.1 GB in its Mail store before adding test
fixtures. One active Gmail account accounted for 9.63 GB: 5.39 GB of `.emlxpart`
files, 3.02 GB of `.emlx` files and 1.22 GB of decoded attachments. Only the current
V10 store was present; metadata checks did not identify obsolete account stores
or an obvious duplicate-cache cleanup. Local-only and imported mail was kept.
The separate Mail Downloads cache initially used approximately 117 MB.

These are allocated bytes, not safely removable estimates. Attachment-payload
restoration and hashing tests used generated messages only. A separate read-only
local duplicate audit compared MIME part lengths and hashes without uploading
message contents.

### Download preferences and the Gmail candidate

Mail offers All, Recent and None for Download Attachments. Apple's documentation
says Recent covers 15 months and media attachments, including images, PDFs,
video and audio, always download. None is neither a GB limit nor a promise to
remove existing media. A native All → None → All test left both Mail cache
services reporting zero at urgencies 1, 3 and 4.

The legacy scripting `messageCaching` property cannot provide header-only mail.
The installed dictionary explicitly deprecates the no-copy and read-only-message
modes. Native code clamps those modes to the all-messages/omit-attachments policy.
The older scripting labels also do not describe every current numeric policy;
writing guessed values would not establish a new supported capability.

Google officially documents [IMAP folder-size limits and excluding folders from
synchronization](https://support.google.com/mail/answer/7126229?hl=en). The live
Gmail account offered that setting and was set to unlimited. A message-count
window could reduce what Mail mirrors while retaining older mail on Gmail.
It affects all IMAP clients for that account and is not a byte quota. The real
setting was tested temporarily as described below, then restored to Unlimited.

Google's [ImapSettings API](https://developers.google.com/workspace/gmail/api/reference/rest/v1/ImapSettings)
accepts `maxFolderSize` values `0`, `1000`, `2000`, `5000` and `10000`, with `0`
meaning unlimited messages per folder. [Updating it](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/updateImap)
requires `gmail.settings.basic`, which Google classifies as a
[restricted scope](https://developers.google.com/workspace/gmail/api/auth/scopes).
A public integration needs Google's scope verification as well as real-account
behavior tests. It must preserve the separate expunge/deletion-policy fields.

### A modeled IMAP window reclaimed and restored local files

Four self-generated PDFs were served by a read-only IMAP fixture bound only to
the Mac's loopback interface. All four native Mail attachment copies initially
matched their source SHA-256 hashes. Hiding the older two messages while retaining
all complete server MIME originals let Mail remove their local rows and files.
The test account's allocated storage fell from 4,235,264 to 2,121,728 bytes.

Re-exposing the older messages with fresh IMAP UIDs produced new native files
with new inodes and exactly matching payload hashes. A second shrink followed by
a normal Mail quit/reopen retained the 2,121,728-byte cache and two visible
messages. The second restore again matched all four native attachment hashes;
all server MIME originals remained unchanged throughout both cycles.

This models a server visibility change, not Gmail's actual cap selection or UID
semantics. Older hidden messages are absent from Mail until re-exposed. The test
does not establish a GB quota or per-item eviction that keeps older headers.

### A temporary real Gmail window reclaimed 1.64 GB

An approved limit of 10,000 messages per IMAP folder reduced the tested account's
native allocation from 9,654,591,488 to 8,015,896,576 bytes: 1,638,694,912 bytes
reclaimed. Canonical All Mail stabilized at exactly 10,000 rows. The same row
count, 94,174 file inodes and allocation survived normal Mail quit/relaunch and
synchronization. Expunge/deletion policies were preserved. Two older messages
removed locally still matched exact Gmail ID searches, without reading their bodies.

Restoring Unlimited triggered a local index reset and history backfill. The saved
Unlimited setting was verified after reopening Gmail settings, with the original
expunge policies unchanged. All Mail returned to its original 117,821 active rows
and stayed at that count across three samples. This verifies index restoration,
not a byte-for-byte audit or complete download of every personal message body.
Returning to the larger window can redownload data and consume the reclaimed
space. The two older controls returned with matching Message-ID,
date and message-size metadata. Opening them through native Mail produced fresh
cache file inodes. Both had already been read; their personal bodies were not
parsed or hashed by the test. This is a per-folder message count affecting all
IMAP clients for the account, not a Mac-only or GB quota, and must not be enforced
in a loop.

After that proper native cache reset, Mail's Save Attachment action recovered
the generated 4 MiB ZIP and 8,388,659-byte PDF fixture with exact source hashes.
The valid 33,272-byte PDF also appeared in a fresh native row and decoded cache
inode with its original SHA-256. The large PDF was deliberately malformed;
successful saving does not establish rendering. This narrows the earlier failed
hand-removal result: proper native recovery can work, but retained imported copies
still prevent independent attribution to a fresh server transfer.

An app integration needs Google's restricted settings scope and public-app
verification described above. This investigation ships no Gmail setting or Mail quota.

### Remaining Drafts material was preserved

About 7.31 GB remained in the physical Drafts tree, versus 692 MB in the capped
All Mail tree. Drafts included all 4,376 remaining EMLX-part files, totaling
5.39 GB, plus 1.08 GB of full EMLX and 787 MB of decoded attachments. Those part
filenames had no current message-row match. Native Drafts metadata held 1,489
rows, 1,487 marked deleted and two active.

This suggests accumulated historical or unindexed draft material. It establishes
neither duplicate content nor cloud coverage or safe removability. The files were
preserved. A personal Drafts rebuild or orphan-file deletion is not offered.

### Generated Drafts replacement and rebuild

A separate read-only loopback Drafts mailbox exposed one generated unsent message
at a time. Versions 1 and 2 shared a Message-ID with different 2 MiB PDFs; version
3 used a distinct Message-ID. Each replacement received a fresh UID. Native Mail
removed the preceding version's files and held steady at three files and
2,105,344 allocated bytes. Every current PDF matched its source SHA-256. This
server-side replacement model did not reproduce the historical Drafts footprint
and does not establish how Mail's actual compose autosave assigns identities.

Rebuild of only that synthetic Drafts mailbox produced a new native row and PDF
inode with the same payload hash and allocation; the fixture logged fresh body
fetches. A second rebuild removed a deliberately inserted 2 MiB generated
filename sentinel beside the old message files. The mailbox temporarily had no
indexed messages, then an explicit fixture-account sync restored the current PDF
with its original hash. The sentinel was named `.emlxpart` but was not a valid
native legacy part: this tests directory coverage, not legacy-part correctness.

Rebuild can therefore remove unindexed material in this controlled case; it is
not an orphan-inspection operation. That makes verified server coverage essential
before applying it to valuable historical drafts. No personal Drafts mailbox was
rebuilt or cleaned. No composer or Send action was used, the test account was
disabled afterward, all generated server originals remained unchanged, and the
temporary server was stopped.

### A test-label rebuild did not prove reclamation

Three generated messages were imported through Mail and copied into a dedicated
IMAP test label. The 4 MiB ZIP payload and a valid 33,272-byte PDF were read back
through the Gmail API with SHA-256 matching their local sources. Another PDF
fixture deliberately lacked a complete renderable document structure.

With Download Attachments temporarily set to None, only the generated test label
was rebuilt through Mail. The ZIP's server hash still matched afterward. Mail
stored the two initial remote messages in Gmail's canonical All Mail cache,
using 13,725,696 allocated bytes; the label's own directory was not that physical
cache. Rebuilding the label did not demonstrate eviction of those files.
No personal mailbox or the full All Mail store was rebuilt. All was restored.

A separate reversible test retained the generated ZIP message's complete EMLX
and decoded attachment outside Mail, with independent verified backups. Native
IMAP traces confirmed fresh body-structure, header and text-part fetches for the
exact server UID. The attachment stayed at 1% and Save Attachments produced no
file; no ZIP-part fetch was observed. Its new partial EMLX contained no attachment
payload. The partial was retained and both originals were returned with their
original inodes and hashes. This bypassed Mail's native flag-and-cache reset.
A later owned-record check found both cached and partial flags set; stale
bookkeeping is a plausible, unproven cause of the 1% stall. This filesystem test
does not rule out restoration after proper native invalidation.

### Complete local sources cover little of the attachment store

A read-only audit checked 2,851 decoded attachment files occupying 1,219,309,568
allocated bytes. Complete EMLX sources contained identical payloads at the same
MIME address for 140 files. A second lookup across message identities and other
local rows added one file. Combined, the proven duplicates occupied 24,424,448
allocated bytes, about 2% of the decoded footprint. Unknown layouts and incomplete
sources were excluded. External EMLX parts supplied no same-row or whole-file
duplicate candidates. This is not proof that excluded items lack cloud copies.

A generated valid PDF tested the narrower duplicate-removal route. Its complete
MIME original stayed unchanged in Mail while the decoded copy was retained in
quarantine, with an independent backup. Opening the attachment produced a new
Mail Downloads copy that rendered successfully and matched SHA-256. Mail did
not recreate the missing decoded-cache file. Other local source copies remained,
so this was not independent server-restoration proof. The original decoded file
was returned with its original inode and hash.

This route has limited verified coverage and does not establish reliable automatic
cache rebuilding or meaningful GB-scale reclamation. It is not implemented as
a general Mail cleaner.

### Opened attachment copies did not clear on quit

General → Remove unedited downloads was temporarily changed from After Message
is Deleted to When Mail Quits. Two normal quit cycles reclaimed no measured
space. The second control used the valid generated PDF, successfully displayed
in Preview and closed without edits before quitting Mail. Its cached copy
remained. After Message is Deleted was then restored.

Native inspection found that this policy processes a tracked opened-attachment
list rather than scanning all of Mail Downloads. Its enable gate defaults to
true; an absent preference is not a disabled feature. No saved tracking list
was found after these tests. A statically inspected successful-open branch skips
purge-entry registration, which is consistent with the observations. The live
call stack was not instrumented, so that branch is an explanation candidate,
not a proven cause for every current attachment open or macOS version.

The separate periodic Mail cache extension excludes freshly accessed downloads
for 24 hours. It is not the same contract as the quit setting. Neither route
justifies advertising immediate verified cleanup on this Mac, forging tracking
entries or writing an undocumented enable flag.

### Zero native estimates may be incomplete

A standalone `MFCacheDeleteAttachmentPurger` diagnostic found no accounts despite
configured native accounts. Its result was invalid; `tools/mail-storage-probe.m`
reports `mail_accounts_unverified`. The same `MFAccount.sharedAccountStore` query
used by Apple's storage component returned permission denied, not an empty
account list. Mail Automation permission did not grant this private account access.

The actual Apple Mail cache extension did see five active accounts. Requests to
`com.apple.MailCacheDelete` and `com.apple.MAIL`, with native service filtering,
no-cache and urgencies 1, 3 and 4, still returned zero. In the same windows, its
metadata query logged connection invalidation and restarts. Read-only controls
found no indexed Mail candidates despite volume indexing being enabled. The
zero may therefore reflect incomplete metadata discovery; its cause is not
proven, and zero is not a complete inventory of removable mail. No index rebuild
or private purge was used to force a result.

### External per-message eviction remains unverified

A separately signed helper had user-authorized Mail automation access. Account
retrieval and even Mail's app-name query repeatedly timed out through raw Apple
events, ScriptingBridge and the GUI parent. A self-event control completed in
0.04 seconds. Mail receiver logs showed an entitlement handshake followed by
`AEProcessMessage(), err=paramErr`; the exact cause remains unknown. The failed
prototype and temporary permission are not part of the production app.

A native `removeMessageDataToRetryDownloadForMessage…` wrapper deletes local
message files without checking a server copy itself. It was not called on personal
mail. Initial owned-message metadata getters failed before library initialization;
the apparent reader-status route also checks out a writer and sets up a database,
so it was not run on the personal store.

A later isolated process initialized 55 native tables in a fresh generated Mail
store, wrote a complete IMAP fixture through Mail's native message writer and read
its exact native message header. Kernel restrictions denied personal Mail,
Accounts and Preferences writes, plus network and daemon access. The fixture's native
cache path remained unresolved without a legitimate global Mail account context,
so invalidation was refused before execution. This proves a limited isolated
bootstrap, not a usable external cleaner. MailKit did not expose download eviction.

Native reclamation was demonstrated for the modeled window and the temporary real
Gmail window. Generated cache payloads recovered with matching hashes, subject to
the source-attribution limit above. External per-message eviction remains
unverified. Investigation code deleted no personal mail or attachments; native
Mail managed its mirror during the approved window test. Tested preferences were
restored. This branch offers neither Mail cleanup nor a Mail quota.

## Music, TV and other stores

Music's public library reader connected successfully, as did a native read-only
storage query through its framework client. Apple's own storage extension passes
an array of numeric persistent IDs to
`synchronousRemoveDownloadForTracks:withReply:`; its reply contains an error,
not a library-deletion result. The native enum table confirmed subscription
catalogue items as `CloudType == 8`. This is a concrete candidate for download
management, distinct from deleting a song from the library.

The initial library metadata contained 1,468 cloud records and no local track
locations. Some records are playlist-only, so a candidate was checked against
the real Songs view before testing. A native Download action for that one
catalogue track failed with the explicit Apple Account associated-device limit:
store-request error 7505, underlying status 3058. No local test download was
created and the prepared one-ID removal helper was not invoked. No device was
de-associated or account signed out. Music's Account Settings also failed to
load its JavaScript account page despite successful HTTP responses; that is a
separate observed failure, not proof that the removal API cannot work. The
official alternative through TV loaded the account overview, but its device
management page also showed Cannot Connect. No device was removed to bypass
that limit.

Imported/matched music is not treated as an exact original-file backup: Apple's
cloud service can convert formats. Purchased, subscription, uploaded and local-only
items must not be combined into a generic eviction policy without separate proof.

Books' native BookKit connection rejected an ordinary helper for its missing
private entitlement. The verified implementation uses the official iCloud
document API instead. PDFs and EPUB packages in the verified Books container are
handled differently from purchases or audiobooks outside that storage.

For Voice Memos, a MacCatalyst diagnostic could load the native framework and
inspect local-asset eviction methods. The external recording-service protocol
did not expose a corresponding per-record eviction operation. Notes also has
internal purge methods alongside local database deletion, without a verified
third-party upload/restore contract. Neither application's local store was changed.

Podcasts and Safari offline content can have native download removal, but their
iCloud-synced lists do not establish a durable copy of the original episode or
webpage. Publisher content may disappear. Those stores do not meet this feature's
requirement to preserve a restorable cloud original merely by retaining a list
entry or subscription.
