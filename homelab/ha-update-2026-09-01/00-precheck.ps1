param([string]$EvidenceDir = "C:\Users\mrshr\tmp\ha-update")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HaRest = 'C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1'
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$StartedAt = Get-Date
$Assertions = New-Object System.Collections.ArrayList
$CameraBaseline = @()

if (-not (Test-Path -LiteralPath $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

function Add-Assertion {
    param([string]$Name, [bool]$Passed, [object]$RawValue)
    [void]$script:Assertions.Add([pscustomobject]@{
        name = $Name
        passed = $Passed
        raw_value = $RawValue
    })
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

function Get-SupervisorData {
    param([object]$Response)
    if ($null -ne $Response.PSObject.Properties['data']) {
        return $Response.data
    }
    return $Response
}

try {
    $config = Invoke-HaJson -Method GET -Path '/api/config'
    Add-Assertion -Name 'Home Assistant state is RUNNING' -Passed ([string]$config.state -eq 'RUNNING') -RawValue $config.state
    Add-Assertion -Name 'Home Assistant Core version is 2026.8.3' -Passed ([string]$config.version -eq '2026.8.3') -RawValue $config.version

    $states = @(Invoke-HaJson -Method GET -Path '/api/states')
    $updatesInProgress = @($states | Where-Object {
        $_.entity_id -like 'update.*' -and
        $null -ne $_.attributes.PSObject.Properties['in_progress'] -and
        $_.attributes.in_progress -eq $true
    })
    Add-Assertion -Name 'No update entity is in progress' -Passed ($updatesInProgress.Count -eq 0) -RawValue $updatesInProgress

    $now = [DateTimeOffset]::UtcNow
    $recentAutomations = New-Object System.Collections.ArrayList
    foreach ($automation in @($states | Where-Object { $_.entity_id -like 'automation.*' })) {
        if ($null -eq $automation.attributes.PSObject.Properties['last_triggered'] -or $null -eq $automation.attributes.last_triggered) {
            continue
        }
        $lastTriggered = [DateTimeOffset]::Parse([string]$automation.attributes.last_triggered).ToUniversalTime()
        $ageSeconds = ($now - $lastTriggered).TotalSeconds
        if ($ageSeconds -ge 0 -and $ageSeconds -le 120) {
            [void]$recentAutomations.Add([pscustomobject]@{
                entity_id = $automation.entity_id
                last_triggered = $automation.attributes.last_triggered
                age_seconds = [math]::Round($ageSeconds, 1)
            })
        }
    }
    Add-Assertion -Name 'No automation triggered in the last 120 seconds' -Passed ($recentAutomations.Count -eq 0) -RawValue $recentAutomations

    $supervisor = Get-SupervisorData -Response (Invoke-HaJson -Method GET -Path '/api/hassio/supervisor/info')
    Add-Assertion -Name 'Supervisor is healthy' -Passed ($supervisor.healthy -eq $true) -RawValue $supervisor.healthy
    Add-Assertion -Name 'Supervisor installation is supported' -Passed ($supervisor.supported -eq $true) -RawValue $supervisor.supported

    $hostInfo = Get-SupervisorData -Response (Invoke-HaJson -Method GET -Path '/api/hassio/host/info')
    $diskFreeGb = [double]$hostInfo.disk_free
    Add-Assertion -Name 'Host has more than 2 GB free' -Passed ($diskFreeGb -gt 2.0) -RawValue ([pscustomobject]@{ disk_free_gb = $diskFreeGb; response = $hostInfo })

    $targets = @(
        [pscustomobject]@{ entity_id = 'update.frigate_update'; installed = 'v5.15.4'; latest = 'v5.15.5' },
        [pscustomobject]@{ entity_id = 'update.cloudedge_cloudplus_meari_update'; installed = 'v0.3.0'; latest = 'v0.3.1' },
        [pscustomobject]@{ entity_id = 'update.advanced_camera_card_update'; installed = 'v7.27.4'; latest = 'v8.0.1' }
    )
    foreach ($target in $targets) {
        $entity = @($states | Where-Object { $_.entity_id -eq $target.entity_id }) | Select-Object -First 1
        $matches = $null -ne $entity -and
            [string]$entity.attributes.installed_version -eq $target.installed -and
            [string]$entity.attributes.latest_version -eq $target.latest
        Add-Assertion -Name ("Target versions match for {0}" -f $target.entity_id) -Passed $matches -RawValue $entity
    }

    $CameraBaseline = @($states | Where-Object { $_.entity_id -like 'camera.*' } | Sort-Object entity_id)
    Add-Assertion -Name 'Camera discovery baseline captured' -Passed ($CameraBaseline.Count -gt 0) -RawValue $CameraBaseline
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
    camera_baseline = $CameraBaseline
}
$evidencePath = Join-Path $EvidenceDir ("{0}-{1}.json" -f $ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

if ($failed.Count -gt 0) {
    Write-Host ("{0} FAIL ({1} failed of {2}; evidence: {3})" -f $ScriptName, $failed.Count, $Assertions.Count, $evidencePath)
    exit 1
}
Write-Host ("{0} PASS ({1} assertions; evidence: {2})" -f $ScriptName, $Assertions.Count, $evidencePath)
exit 0
