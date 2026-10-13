# LightNAS — storage agent and operation framework

A dependency-free Node.js 22+ storage control plane, responsive console, privileged Unix-socket agent, and Debian/Ubuntu installer. This is a storage engineering milestone, not the full NAS operating system in the product vision.

## Milestone coverage

| Requirement | Implementation |
|---|---|
| Disk enumeration | lsblk, sysfs, udev, read-only wipefs signatures, SMART/NVMe health |
| Independent resource models | Disks, detected pools, filesystems, persisted managed shares, health |
| Exact mutation previews | Device identities, sizes, existing signatures, commands/layout or before/after configuration, affected services, cancellation/rollback limits |
| Narrow privileged execution | Typed allowlisted operations, root-owned service, authenticated Unix socket; unprivileged web broker |
| Operation lifecycle | Durable job state, progress stream with replay, logs, cancellation before commit, restart interruption detection, rollback metadata |
| Samba/NFS adapters | Explicit access, config injection checks, deterministic rendering, full Samba candidate validation, activation/recovery, approved restore previews, no-op detection |

Implemented operations:

- `shares.replace`: replaces all LightNAS-managed SMB/NFS shares. Does not delete files or change Unix permissions.
- `filesystem.create`: ext4 or Btrfs on one blank physical disk.
- `pool.create`: Btrfs RAID1 data and metadata on two or more blank physical disks.

Disk initialization requires explicit host opt-in. It rejects disks without stable serial/WWN, unavailable safety inventory, existing signatures, partitions, mounted filesystems, holders, read-only state, duplicate identities or unsupported paths. The exact disk confirmation phrase and preview hash are required. Filesystem writes are irreversible: no automatic data rollback is promised.

## Run in development

```sh
npm test
NAS_AGENT_TOKEN='<random secret of at least 32 characters>' npm start
```

Open `http://127.0.0.1:3080` and enter the token. The standalone development server is read-only; mutation requests require the root agent. Tokens stay in browser memory. Disk selection, exact impact review, progress, logs, cancellation and configuration rollback previews are available in the console.

## Install on a Debian/Ubuntu test appliance

After this branch is published/merged, clone the version you intend to test, inspect it, and run:

```sh
sudo bash install.sh
```

The installer uses `/opt/lightnas` and preserves existing Git installations with clean, fast-forward-only updates. It installs Node.js/npm, curl/git, certificates, SMART, filesystem tools, Samba and NFS; creates a random administrator token; installs the two services; and adds a managed Samba include inside the global section without replacing the existing configuration. It does not initialize disks or grant share access automatically.

This installer is intended for the repository’s published default branch; before publication it cannot fetch this local implementation from GitHub.

The web service runs as `lightnas`. The storage agent runs as root. Source is root-owned; the socket is root:lightnas mode 0660; the token is root:lightnas mode 0640. Membership in the `lightnas` group grants access to the administrative broker and must be restricted.

The console binds to localhost. For remote access use an SSH tunnel or TLS reverse proxy. The current identity mechanism is a single administrator API token, not per-user RBAC, password login, MFA or SSO.

Prepare existing share directories under `/srv/lightnas` and provision Unix/Samba users and filesystem permissions separately. The adapter checks Unix user existence and does not create accounts or ACLs.

To enable disk initialization explicitly on a disposable test appliance:

```sh
sudo systemctl edit lightnas-storage
```

Add:

```ini
[Service]
Environment=NAS_ALLOW_STORAGE_INITIALIZATION=1
```

Then restart the agent. Review the exact devices and irreversible-write warning in the console before approving. No destructive command has been run as part of implementation or automated tests.

## API

Every API request requires `Authorization: Bearer <token>`. The UI shell contains no private inventory. Direct root-agent requests use `/run/lightnas/storage.sock`.

| Method | Route | Purpose |
|---|---|---|
| GET | /v1/inventory | Disks, pools, filesystems, shares, health |
| POST | /v1/preview | Create a five-minute impact preview |
| POST | /v1/jobs/:id/approve | Submit approvalHash and exact confirmation for disk operations |
| POST | /v1/jobs/:id/cancel | Cancel before commit |
| POST | /v1/jobs/:id/rollback-preview | Preview restoration of saved managed share configuration |
| GET | /v1/jobs | Job history |
| GET | /v1/jobs/:id | Status, logs, output and rollback metadata |
| GET | /v1/jobs/:id/events?after=0 | Incremental progress events |
| GET | /v1/jobs/:id/stream | Server-sent events; supports Last-Event-ID |

Share preview:

```json
{"type":"shares.replace","shares":[{"name":"documents","path":"/srv/lightnas/documents","protocol":"smb","readOnly":false,"users":["alice"]},{"name":"linux","path":"/srv/lightnas/linux","protocol":"nfs","readOnly":true,"clients":["192.168.0.0/24"]}]}
```

Filesystem preview (use an actual stable inventory ID):

```json
{"type":"filesystem.create","diskIds":["DISK_SERIAL"],"filesystem":"ext4","label":"data"}
```

Pool preview:

```json
{"type":"pool.create","diskIds":["DISK_A_SERIAL","DISK_B_SERIAL"],"filesystem":"btrfs","profile":"raid1","label":"mirror"}
```

The resulting whole-device filesystem is verified by inventory. Mounting, boot-time mount persistence and user permission setup are separate work; successful initialization does not imply that a share is ready.

## Validation and remaining work

Automated tests use fake block devices/commands and cover dangerous input rejection, stale previews, tampering, exact-device approval, cancellation, output verification, rollback, restart recovery, API authentication and event streaming. Installer shell syntax and browser JavaScript syntax are checked. The Unix-socket broker integration test skips explicitly when the runtime prohibits socket creation; that restriction applies in the current execution environment. No browser executable is available here for visual validation. Live Samba/NFS service integration, installer execution, disk formatting, capacity/failure behavior, and visual desktop/mobile browser validation remain unverified on real appliance hardware.

Progress percentages represent phases, not measured filesystem-command completion. Full health collection is separate from fresh safety checks so SMART probes are not repeated during every approval. Inventory scans are otherwise uncached.

NFS validation is strict typed input followed by exportfs activation; failed activation restores prior managed configuration and retries reload. Multiple files are fsynced individually, not committed as one filesystem transaction. Interrupted jobs require inspection and an approved recovery preview rather than automatic replay. Host processes outside this agent can still race with storage checks; exclusive host maintenance during initialization remains necessary. Jobs are capped at 1,000 records pending archival.

Not yet implemented: partitioning, mount/unmount workflows, Linux md RAID creation, pool expansion/removal, snapshots, encryption, ACL/quota management, disk replacement, per-user identity/RBAC, installer ISO, apps, backups, or the rest of the operating-system roadmap.

See [the design brief](Lightweight_AI_NAS_OS_Design_Brief.md) for the complete phased vision.
