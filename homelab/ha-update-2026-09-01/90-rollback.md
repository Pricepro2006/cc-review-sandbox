# Rollback runbook

Use the least disruptive rollback that addresses the failure. Preserve the entire evidence directory before rolling anything back. Do not delete backups, VM snapshots, or disks.

## Advanced Camera Card only

1. In HACS, open Advanced Camera Card, choose **Redownload**, select version `v7.27.4`, and complete the download.
2. Restore every dashboard from its `lovelace-<url_path>-before.json` dump. The following Windows PowerShell 5.1 snippet reads the dashboard/file mapping from the latest successful `40-update-card-*.json` evidence file and sends each configuration through the existing authenticated WebSocket helper:

   ```powershell
   $EvidenceDir = 'C:\Users\mrshr\tmp\ha-update'
   $HaWs = 'C:\Users\mrshr\Documents\homelab-tools\ha-ws.ps1'
   $run = Get-ChildItem -LiteralPath $EvidenceDir -Filter '40-update-card-*.json' -File |
       Sort-Object LastWriteTime -Descending |
       Select-Object -First 1 |
       Get-Content -Raw |
       ConvertFrom-Json

   foreach ($dashboard in @($run.dashboard_dumps)) {
       $dump = Get-Content -LiteralPath $dashboard.before_file -Raw | ConvertFrom-Json
       if ($null -ne $dump.PSObject.Properties['result']) {
           $config = $dump.result
       }
       else {
           $config = $dump
       }
       $message = [ordered]@{
           type = 'lovelace/config/save'
           config = $config
       }
       if (-not [string]::IsNullOrWhiteSpace([string]$dashboard.url_path)) {
           $message['url_path'] = [string]$dashboard.url_path
       }
       $messageJson = $message | ConvertTo-Json -Depth 20 -Compress
       & $HaWs -MsgJson $messageJson
   }
   ```

3. Reload the dashboard in a fresh browser session and verify the camera cards. Re-run `50-verify-card.ps1` only after the restored files and resource version are confirmed.

## HACS integrations

Use the partial-backup slug recorded by `10-backup-*.json`. Restoring the Home Assistant portion rolls back both custom integrations and Home Assistant configuration to the pre-update point.

```powershell
$EvidenceDir = 'C:\Users\mrshr\tmp\ha-update'
$HaRest = 'C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1'
$run = Get-ChildItem -LiteralPath $EvidenceDir -Filter '10-backup-*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    Get-Content -Raw |
    ConvertFrom-Json
$slug = [string]$run.backup.slug
if ([string]::IsNullOrWhiteSpace($slug)) { throw 'No backup slug was recorded; stop.' }
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
