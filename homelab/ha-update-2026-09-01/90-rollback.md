# Rollback runbook

Use the least disruptive rollback that addresses the failure. Preserve the entire evidence directory before rolling anything back. Do not delete backups, VM snapshots, or disks.

## Advanced Camera Card only

1. In HACS, open Advanced Camera Card, choose **Redownload**, select version `v7.27.4`, and complete the download.
2. Restore every dashboard from its `lovelace-<url_path>-before.json` dump. The following Windows PowerShell 5.1 snippet reads the dashboard/file mapping from the latest successful `40-update-card-*.json` evidence file and sends each configuration through the existing authenticated WebSocket helper:

   ```powershell
   $EvidenceDir = 'C:\Users\mrshr\tmp\ha-update'
   $HaWs = 'C:\Users\mrshr\Documents\homelab-tools\ha-ws.ps1'
   $ErrorActionPreference = 'Stop'   # a missing before_file must throw, not print a false SKIP
   # Only a PASSED 40 run holds a trustworthy before-dump mapping; a failed re-run may be newer.
   $run = Get-ChildItem -LiteralPath $EvidenceDir -Filter '40-update-card-*.json' -File |
       Sort-Object LastWriteTime -Descending |
       ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } |
       Where-Object { $_.passed -eq $true } |
       Select-Object -First 1
   if ($null -eq $run) { throw 'No PASSED 40-update-card evidence file found; stop.' }

   foreach ($dashboard in @($run.dashboard_dumps)) {
       $dump = Get-Content -LiteralPath $dashboard.before_file -Raw | ConvertFrom-Json
       # Guard (round 2, NEW-MED-1): a before-dump may be a websocket ERROR envelope (config_not_found)
       # for an auto-generated or YAML dashboard. Never send that to lovelace/config/save — skip it.
       $isStorageDump = ($null -ne $dump.PSObject.Properties['success']) -and ($dump.success -eq $true) -and
           ($null -ne $dump.PSObject.Properties['result'])
       if (-not $isStorageDump) {
           Write-Host ("SKIP {0}: before-dump is not a successful stored config (nothing to restore)" -f $dashboard.name)
           continue
       }
       $message = [ordered]@{
           type = 'lovelace/config/save'
           config = $dump.result
       }
       if (-not [string]::IsNullOrWhiteSpace([string]$dashboard.url_path)) {
           $message['url_path'] = [string]$dashboard.url_path
       }
       $messageJson = $message | ConvertTo-Json -Depth 20 -Compress
       # ha-ws.ps1 only reports via -OutFile; read it back so each restore has a readable success/failure.
       $replyFile = Join-Path $EvidenceDir ("rollback-{0}-{1}.json" -f $dashboard.name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
       & $HaWs -MsgJson $messageJson -OutFile $replyFile | Out-Null
       if (-not (Test-Path -LiteralPath $replyFile)) { throw "ha-ws.ps1 wrote no reply for $($dashboard.name); stop." }
       $reply = Get-Content -LiteralPath $replyFile -Raw | ConvertFrom-Json
       if ($reply.success -ne $true) { throw "Restore of $($dashboard.name) failed: $replyFile" }
       Write-Host ("RESTORED {0} ({1})" -f $dashboard.name, $replyFile)
   }
   ```

3. Reload the dashboard in a fresh browser session and verify the camera cards. Re-run `50-verify-card.ps1` only after the restored files and resource version are confirmed.

## HACS integrations

Use the partial-backup slug recorded by `10-backup-*.json`. Restoring the Home Assistant portion rolls back both custom integrations and Home Assistant configuration to the pre-update point.

```powershell
$EvidenceDir = 'C:\Users\mrshr\tmp\ha-update'
$HaRest = 'C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1'
$ErrorActionPreference = 'Stop'
$KnownSlug = '82373c64'   # pre-hacs-update-2026-09-01 partial backup taken by the 2026-09-01 run
# A re-run of 10-backup creates a fresh POST-update backup before failing on the existing snapshot name,
# so the newest evidence file can carry the WRONG slug. Use only a PASSED run, and require it to match the known slug.
$run = Get-ChildItem -LiteralPath $EvidenceDir -Filter '10-backup-*.json' -File |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } |
    Where-Object { $_.passed -eq $true } |
    Select-Object -First 1
if ($null -eq $run) { throw 'No PASSED 10-backup evidence file found; stop.' }
$slug = [string]$run.backup.slug
if ([string]::IsNullOrWhiteSpace($slug)) { throw 'No backup slug was recorded; stop.' }
if ($slug -ne $KnownSlug) { throw "Evidence slug $slug does not match the known pre-update slug $KnownSlug; stop and inspect." }
$body = '{"homeassistant":true,"folders":["share","ssl"]}'
& $HaRest -Method POST -Path ("/api/hassio/backups/{0}/restore/partial" -f $slug) -BodyJson $body
```

Wait for Home Assistant to return, then run the core verification checks appropriate to the restored versions. Do not proceed if the evidence does not contain a valid slug.

## VM snapshot (last resort)

This rollback loses recorder history and every other VM change made after the snapshot:

```powershell
wsl -- ssh root@10.0.0.101 "qm rollback 105 pre-hacs-2026-09-01"
```

Confirm with the operator before using this last-resort rollback. The `unused1` old disk retained from the 2026-08-17 cutover is the deep fallback and must never be deleted.


## Correction (FableGate review 2026-09-01)

`qm rollback 105 pre-hacs-2026-09-01` leaves the VM **stopped**. Follow with `qm start 105` (or add `--start` if the host's `qm` supports it) and then wait for `http://10.0.0.50:8123/api/config` to report `RUNNING`. Recorder history since the snapshot is lost; this remains the last resort.

**Dashboard restore guard (FableGate round 2, NEW-MED-1):** a `lovelace-<x>-before.json` may be a websocket *error envelope* (`success:false`, `error.code: config_not_found`) for an auto-generated or YAML-mode dashboard — `40-update-card.ps1` tolerates that on purpose. **Never send such a dump to `lovelace/config/save`**: it would convert the dashboard into a storage dashboard whose config is the error object. Before restoring any dump, check `success -eq $true` and that a `result` property exists; skip the file otherwise.

**Follow-up (FableGate review 3, MED-3):** the guard above is now inside the executable snippet (`success -eq $true` + `result` present, else skip), each restore reads its reply via `-OutFile`, and both evidence pickers use only `passed -eq $true` runs (the HACS one also pins the known slug).
