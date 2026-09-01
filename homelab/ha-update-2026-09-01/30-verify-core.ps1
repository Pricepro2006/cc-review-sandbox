param([string]$EvidenceDir = "C:\Users\mrshr\tmp\ha-update")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HaRest = 'C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1'
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$StartedAt = Get-Date
$Assertions = New-Object System.Collections.ArrayList
$ConfigEntries = @()
$CameraStates = @()

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

try {
    $apiReady = $false
    $lastApiResult = $null
    $deadline = (Get-Date).AddMinutes(15)
    do {
        try {
            $lastApiResult = Invoke-HaJson -Method GET -Path '/api/'
            $apiReady = [string]$lastApiResult.message -eq 'API running.'
        }
        catch {
            $lastApiResult = [pscustomobject]@{ error = ($_ | Out-String) }
        }
        if ($apiReady) { break }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    Add-Assertion -Name 'Home Assistant API returned API running within 15 minutes' -Passed $apiReady -RawValue $lastApiResult

    if ($apiReady) {
        Start-Sleep -Seconds 30

        $ConfigEntries = @(Invoke-HaJson -Method GET -Path '/api/config/config_entries/entry')
        Add-Assertion -Name 'Full config-entry list was retrieved' -Passed ($ConfigEntries.Count -gt 0) -RawValue $ConfigEntries

        $criticalDomains = @('frigate', 'cloudplus', 'mqtt', 'zha', 'tplink', 'proxmoxve', 'hacs')
        foreach ($domain in $criticalDomains) {
            $entries = @($ConfigEntries | Where-Object { [string]$_.domain -eq $domain })
            $loaded = $entries.Count -gt 0 -and @($entries | Where-Object { [string]$_.state -ne 'loaded' }).Count -eq 0
            Add-Assertion -Name ("Critical integration is loaded: {0}" -f $domain) -Passed $loaded -RawValue $entries
        }

        $unexpectedRetries = @($ConfigEntries | Where-Object {
            [string]$_.state -eq 'setup_retry' -and [string]$_.domain -ne 'ipp'
        })
        Add-Assertion -Name 'No unexpected integration is in setup_retry (ipp is tolerated)' -Passed ($unexpectedRetries.Count -eq 0) -RawValue $unexpectedRetries

        $states = @(Invoke-HaJson -Method GET -Path '/api/states')
        $CameraStates = @($states | Where-Object { $_.entity_id -like 'camera.*' } | Sort-Object entity_id)
        Add-Assertion -Name 'At least six camera entities were discovered' -Passed ($CameraStates.Count -ge 6) -RawValue $CameraStates
        $unavailableCameras = @($CameraStates | Where-Object { [string]$_.state -eq 'unavailable' })
        Add-Assertion -Name 'No discovered camera entity is unavailable' -Passed ($unavailableCameras.Count -eq 0) -RawValue $unavailableCameras

        $updatedTargets = @(
            [pscustomobject]@{ entity_id = 'update.frigate_update'; latest = 'v5.15.5' },
            [pscustomobject]@{ entity_id = 'update.cloudedge_cloudplus_meari_update'; latest = 'v0.3.1' }
        )
        foreach ($target in $updatedTargets) {
            $entity = @($states | Where-Object { $_.entity_id -eq $target.entity_id }) | Select-Object -First 1
            $valid = $null -ne $entity -and [string]$entity.state -eq 'off' -and
                [string]$entity.attributes.installed_version -eq $target.latest -and
                [string]$entity.attributes.latest_version -eq $target.latest
            Add-Assertion -Name ("Updated entity is current and off: {0}" -f $target.entity_id) -Passed $valid -RawValue $entity
        }

        try {
            $tailscaleResponse = Invoke-WebRequest -Uri 'http://100.106.83.68:8123/' -UseBasicParsing -TimeoutSec 30
            Add-Assertion -Name 'Tailscale Home Assistant endpoint returns HTTP 200' -Passed ([int]$tailscaleResponse.StatusCode -eq 200) -RawValue ([pscustomobject]@{ status_code = $tailscaleResponse.StatusCode; status_description = $tailscaleResponse.StatusDescription })
        }
        catch {
            Add-Assertion -Name 'Tailscale Home Assistant endpoint returns HTTP 200' -Passed $false -RawValue ($_ | Out-String)
        }
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
    config_entries = $ConfigEntries
    camera_states = $CameraStates
}
$evidencePath = Join-Path $EvidenceDir ("{0}-{1}.json" -f $ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

if ($failed.Count -gt 0) {
    Write-Host ("{0} FAIL ({1} failed of {2}; evidence: {3})" -f $ScriptName, $failed.Count, $Assertions.Count, $evidencePath)
    exit 1
}
Write-Host ("{0} PASS ({1} assertions; evidence: {2})" -f $ScriptName, $Assertions.Count, $evidencePath)
exit 0
