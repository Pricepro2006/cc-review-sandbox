param([string]$EvidenceDir = "C:\Users\mrshr\tmp\ha-update")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HaRest = 'C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1'
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$StartedAt = Get-Date
$Assertions = New-Object System.Collections.ArrayList
$BackupRecord = $null
$SnapshotName = 'pre-hacs-2026-09-01'

if (-not (Test-Path -LiteralPath $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

function Add-Assertion {
    param([string]$Name, [bool]$Passed, [object]$RawValue)
    [void]$script:Assertions.Add([pscustomobject]@{ name = $Name; passed = $Passed; raw_value = $RawValue })
}

function Invoke-HaJson {
    param([ValidateSet('GET', 'POST')][string]$Method, [string]$Path, [string]$BodyJson)
    if ($PSBoundParameters.ContainsKey('BodyJson')) {
        $jsonText = & $script:HaRest -Method $Method -Path $Path -BodyJson $BodyJson
    }
    else {
        $jsonText = & $script:HaRest -Method $Method -Path $Path
    }
    return ($jsonText | ConvertFrom-Json)
}

function Get-Data {
    param([object]$Response)
    if ($null -ne $Response.PSObject.Properties['data']) { return $Response.data }
    return $Response
}

try {
    $beforeResponse = Get-Data -Response (Invoke-HaJson -Method GET -Path '/api/hassio/backups')
    $beforeSlugs = @($beforeResponse.backups | ForEach-Object { [string]$_.slug })

    $body = '{"name":"pre-hacs-update-2026-09-01","homeassistant":true,"folders":["share","ssl"],"compressed":true}'
    $createResponse = Invoke-HaJson -Method POST -Path '/api/hassio/backups/new/partial' -BodyJson $body
    $createData = Get-Data -Response $createResponse
    $requestedSlug = $null
    if ($null -ne $createData.PSObject.Properties['slug']) { $requestedSlug = [string]$createData.slug }
    Add-Assertion -Name 'Partial backup request returned a slug' -Passed (-not [string]::IsNullOrWhiteSpace($requestedSlug)) -RawValue $createResponse

    $deadline = (Get-Date).AddMinutes(10)
    do {
        $listResponse = Get-Data -Response (Invoke-HaJson -Method GET -Path '/api/hassio/backups')
        $candidates = @($listResponse.backups | Where-Object {
            ($requestedSlug -and [string]$_.slug -eq $requestedSlug) -or
            (([string]$_.name -eq 'pre-hacs-update-2026-09-01') -and ($beforeSlugs -notcontains [string]$_.slug))
        })
        if ($candidates.Count -gt 0) {
            $BackupRecord = $candidates | Sort-Object date -Descending | Select-Object -First 1
            break
        }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    Add-Assertion -Name 'New partial backup appears in backup list' -Passed ($null -ne $BackupRecord) -RawValue $BackupRecord
    if ($null -ne $BackupRecord) {
        Add-Assertion -Name 'Backup metadata includes slug, size, and date' -Passed (
            -not [string]::IsNullOrWhiteSpace([string]$BackupRecord.slug) -and
            $null -ne $BackupRecord.size -and
            -not [string]::IsNullOrWhiteSpace([string]$BackupRecord.date)
        ) -RawValue ([pscustomobject]@{ slug = $BackupRecord.slug; size = $BackupRecord.size; date = $BackupRecord.date })
    }
    else {
        Add-Assertion -Name 'Backup metadata includes slug, size, and date' -Passed $false -RawValue $null
    }

    if (@($Assertions | Where-Object { -not $_.passed }).Count -eq 0) {
        $snapshotOutput = @(& wsl -- ssh root@10.0.0.101 "qm snapshot 105 pre-hacs-2026-09-01 --description 'before HACS updates'" 2>&1)
        $snapshotExitCode = $LASTEXITCODE
        Add-Assertion -Name 'Proxmox VM snapshot command succeeded' -Passed ($snapshotExitCode -eq 0) -RawValue ([pscustomobject]@{ exit_code = $snapshotExitCode; output = $snapshotOutput; snapshot = $SnapshotName })

        $listOutput = @(& wsl -- ssh root@10.0.0.101 'qm listsnapshot 105' 2>&1)
        $listExitCode = $LASTEXITCODE
        $snapshotListed = $listExitCode -eq 0 -and (($listOutput -join "`n") -match ('(?m)^\s*' + [regex]::Escape($SnapshotName) + '(\s|$)'))
        Add-Assertion -Name 'Proxmox snapshot is listed for VM 105' -Passed $snapshotListed -RawValue ([pscustomobject]@{ exit_code = $listExitCode; output = $listOutput; snapshot = $SnapshotName })
    }
    else {
        Add-Assertion -Name 'Proxmox snapshot was attempted only after backup success' -Passed $false -RawValue 'Skipped because the Home Assistant backup assertions failed.'
    }
}
catch {
    Add-Assertion -Name 'Script completed without an unexpected error' -Passed $false -RawValue ($_ | Out-String)
}

$failed = @($Assertions | Where-Object { -not $_.passed })
$evidence = [pscustomobject]@{
    script = $ScriptName
    started_at = $StartedAt.ToUniversalTime().ToString('o')
    finished_at = (Get-Date).ToUniversalTime().ToString('o')
    passed = ($failed.Count -eq 0)
    assertions = $Assertions
    backup = $BackupRecord
    proxmox_snapshot = $SnapshotName
}
$evidencePath = Join-Path $EvidenceDir ("{0}-{1}.json" -f $ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

if ($failed.Count -gt 0) {
    Write-Host ("{0} FAIL ({1} failed of {2}; evidence: {3})" -f $ScriptName, $failed.Count, $Assertions.Count, $evidencePath)
    exit 1
}
Write-Host ("{0} PASS ({1} assertions; evidence: {2})" -f $ScriptName, $Assertions.Count, $evidencePath)
exit 0
