# Home Assistant HACS update runbook — 2026-09-01

These scripts were authored offline and were **NOT executed** against Home Assistant, Proxmox, Tailscale, or any other host. Review them before operator use. They target Home Assistant Core `2026.8.3`, HAOS `18.2`, Supervisor `2026.08.0`, and Proxmox VM `105`.

The toolkit updates only:

- Frigate integration: `v5.15.4` to `v5.15.5`
- CloudPlus/Meari integration: `v0.3.0` to `v0.3.1`
- Advanced Camera Card: `v7.27.4` to `v8.0.1`

It does not connect to or alter the Frigate server at `10.0.0.93`.

## Preparation

Run from Windows PowerShell 5.1 on the operator workstation. The scripts use only the existing helpers below for authenticated Home Assistant REST and WebSocket calls; they never read or implement bearer-token handling:

- `C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1`
- `C:\Users\mrshr\Documents\homelab-tools\ha-ws.ps1`

The default evidence directory is `C:\Users\mrshr\tmp\ha-update`. To use another location, pass the same `-EvidenceDir` value to every script. Preserve that directory as the change record.

## Phase 1 — integrations and Core restart

Run each command separately and inspect its final PASS/FAIL line and JSON evidence before continuing:

```powershell
.\00-precheck.ps1
.\10-backup.ps1
.\20-update-integrations.ps1
.\30-verify-core.ps1
```

Phase 1 must be fully green before Phase 2. In particular, confirm that the partial-backup evidence contains a slug and that `pre-hacs-2026-09-01` appears in the Proxmox snapshot listing. The snapshot name is intentionally constant: a rerun of `10-backup.ps1` fails loudly if the snapshot already exists and never deletes or replaces it. Note that a rerun still requests a fresh Home Assistant partial backup *before* it fails on the snapshot name, so the newest `10-backup-*.json` may be a FAILED run carrying a post-update slug — `90-rollback.md` therefore reads only `passed:true` evidence. Likewise `40-update-card.ps1` refuses to run if any `lovelace-*-before.json` already exists, so the rollback baseline is never overwritten by a rerun; move the old dumps aside deliberately if a fresh baseline is really wanted.

`20-update-integrations.ps1` checks both integrations for the exact approved source and target versions before changing either, updates them sequentially, and then requests the required Home Assistant Core restart. It does not touch Advanced Camera Card.

`30-verify-core.ps1` allows up to 15 minutes for the API to return, waits another 30 seconds, and then validates critical integrations, dynamically discovered cameras, update entities, and Tailscale access. An `ipp` config entry in `setup_retry` is tolerated; other retrying integrations fail verification.

## Phase 2 — Advanced Camera Card migration

Only after every Phase 1 script passes, run:

```powershell
.\40-update-card.ps1
.\50-verify-card.ps1
```

Advanced Camera Card `v8.0.1` changes its automation model to `triggers:`, `conditions:`, and `actions:`. The card auto-migrates convertible configuration. `40-update-card.ps1` captures every dashboard before the update, installs the exact approved card version, and captures every dashboard again. `50-verify-card.ps1` fails if `__UPGRADE_FAILURE__` appears and prints every path-level changed block for operator review. Inspect all printed changes even when the script passes.

## Stop conditions

Stop immediately and do not run the next script if:

- any script prints `FAIL` or exits nonzero;
- any installed or latest version differs from the exact versions above;
- an update or recently triggered automation makes the precheck fail;
- the Home Assistant partial backup lacks a recorded slug, size, or date;
- the Proxmox snapshot command fails or the fixed snapshot name is not listed;
- Core does not return within 15 minutes, a critical integration is not `loaded`, fewer than six cameras are discovered, or any discovered camera is `unavailable`;
- Tailscale or Lovelace does not return HTTP 200;
- Phase 1 is not completely green;
- an after-dump contains `__UPGRADE_FAILURE__`, a dashboard lacks a before/after pair, or any printed migration change looks wrong;
- the Advanced Camera Card resource is not identifiable as `v8.0.1` or a `/hacsfiles/` resource.

Use [90-rollback.md](90-rollback.md) if rollback is needed. Do not improvise a wider change while a gate is red.

## Evidence

Every script creates its evidence directory if needed and writes one timestamped assertion record:

- `00-precheck-<yyyyMMdd-HHmmss>.json` — system gates, exact target versions, camera discovery baseline
- `10-backup-<yyyyMMdd-HHmmss>.json` — backup slug/size/date and VM snapshot command/list results
- `20-update-integrations-<yyyyMMdd-HHmmss>.json` — integration version gates, install polling, restart request
- `30-verify-core-<yyyyMMdd-HHmmss>.json` — API readiness, full config-entry list, cameras, updates, Tailscale
- `40-update-card-<yyyyMMdd-HHmmss>.json` — dashboard file mapping, version gate, install polling
- `50-verify-card-<yyyyMMdd-HHmmss>.json` — upgrade-failure checks, changed blocks, resource and HTTP checks

The card phase also creates:

- `lovelace-dashboards-before.json` and `lovelace-dashboards-after.json`
- `lovelace-<url_path-or-default>-before.json` and `lovelace-<url_path-or-default>-after.json` for every dashboard
- `lovelace-resources.json`

Retain all evidence and dashboard dumps together. Never include secrets or tokens in operator notes; the helpers own authentication.


## FableGate review corrections (2026-09-01, applied by operator session)

- `10-backup.ps1`: `qm listsnapshot` tree-format regex fixed; native `wsl/ssh` calls run with EAP=Continue so 5.1's `2>&1` NativeCommandError cannot mask a successful snapshot.
- `20-update-integrations.ps1`: after requesting the restart, waits (max 2 min) until `/api/config` stops answering, so `30` can never race the old process.
- `30-verify-core.ps1`: readiness now means `/api/config` state `RUNNING` **and** version `2026.8.3` (not `/api/` "API running."); disabled config entries are excluded from the critical-domain check.
- `40-update-card.ps1` / `50-verify-card.ps1`: `ha-ws.ps1` output is read back from `-OutFile` (the helper never writes to the success stream); `config_not_found` for auto-generated/YAML dashboards is tolerated; object-diff single-property bug fixed.
- **Important caveat for Phase 2:** the Advanced Camera Card v8 `triggers:/conditions:/actions:` migration and any `__UPGRADE_FAILURE__` marker are produced **client-side when the card renders**; installing the card does not rewrite stored Lovelace config. Expect the before/after diff to be empty. The dumps remain the rollback baseline. **The migration must be verified in a browser**: hard-refresh (Ctrl+F5) each dashboard that uses the card, open every card with `automations:` configured, and look for the upgrade-failure banner. The HACS resource URL (`?hacstag=`) does not encode the version, so `50`'s resource check confirms presence, not version — the installed version assertion in `40` is the authoritative check.
- **Follow-up PR (FableGate review 3 of the merged toolkit, 3 MED):** `20` no longer treats `Unable to connect` / `actively refused` (TCP connect failures — the POST never reached HA) as a fired restart; `40` refuses to overwrite existing before-dumps; `90-rollback.md` snippets now carry the `config_not_found` guard, read each restore reply via `-OutFile`, and select only `passed:true` evidence (HACS restore pins slug `82373c64`).
