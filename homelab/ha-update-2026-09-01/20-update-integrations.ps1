param([string]$EvidenceDir = "C:\Users\mrshr\tmp\ha-update")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HaRest = 'C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1'
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$StartedAt = Get-Date
$Assertions = New-Object System.Collections.ArrayList
$Targets = @(
    [pscustomobject]@{ entity_id = 'update.frigate_update'; installed = 'v5.15.4'; latest = 'v5.15.5' },
    [pscustomobject]@{ entity_id = 'update.cloudedge_cloudplus_meari_update'; installed = 'v0.3.0'; latest = 'v0.3.1' }
)

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
    # Check both targets before making either change, so any version drift aborts safely.
    foreach ($target in $Targets) {
        $entity = Invoke-HaJson -Method GET -Path ("/api/states/{0}" -f $target.entity_id)
        $matches = [string]$entity.attributes.installed_version -eq $target.installed -and
            [string]$entity.attributes.latest_version -eq $target.latest -and
            $entity.attributes.in_progress -ne $true
        Add-Assertion -Name ("Pre-update versions match for {0}" -f $target.entity_id) -Passed $matches -RawValue $entity
    }

    if (@($Assertions | Where-Object { -not $_.passed }).Count -eq 0) {
        foreach ($target in $Targets) {
            $body = @{ entity_id = $target.entity_id; backup = $false } | ConvertTo-Json -Compress
            $installResponse = Invoke-HaJson -Method POST -Path '/api/services/update/install' -BodyJson $body
            Add-Assertion -Name ("Install service call completed for {0}" -f $target.entity_id) -Passed $true -RawValue $installResponse

            $deadline = (Get-Date).AddMinutes(10)
            $completed = $false
            $lastState = $null
            do {
                Start-Sleep -Seconds 5
                $lastState = Invoke-HaJson -Method GET -Path ("/api/states/{0}" -f $target.entity_id)
                $completed = $lastState.attributes.in_progress -ne $true -and
                    [string]$lastState.attributes.installed_version -eq $target.latest
                if ($completed) { break }
            } while ((Get-Date) -lt $deadline)
            Add-Assertion -Name ("Update completed for {0}" -f $target.entity_id) -Passed $completed -RawValue $lastState
            if (-not $completed) { break }
        }
    }

    if (@($Assertions | Where-Object { -not $_.passed }).Count -eq 0) {
        # HA closes the HTTP connection while shutting down, so the restart POST usually raises
        # "connection was closed" without a response. Treat that as the restart having fired;
        # the went-offline wait below and 30-verify-core are the real gates.
        $restartResponse = $null
        $restartFired = $false
        try {
            $restartResponse = Invoke-HaJson -Method POST -Path '/api/services/homeassistant/restart' -BodyJson '{}'
            $restartFired = $true
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match 'connection was closed|connection that was expected to be kept alive|Unable to connect|actively refused') {
                $restartFired = $true
                $restartResponse = [pscustomobject]@{ note = 'restart POST returned no response (HA closed the connection while shutting down)'; error = $msg }
            }
            else { throw }
        }
        Add-Assertion -Name 'Home Assistant restart service call fired' -Passed $restartFired -RawValue $restartResponse

        # Wait (bounded, 2 min) until the API actually goes away so 30-verify-core cannot race the old process.
        $wentDown = $false
        $downDeadline = (Get-Date).AddMinutes(2)
        do {
            Start-Sleep -Seconds 3
            try { [void](Invoke-HaJson -Method GET -Path '/api/config') }
            catch { $wentDown = $true }
        } while (-not $wentDown -and (Get-Date) -lt $downDeadline)
        Add-Assertion -Name 'Home Assistant API went offline after restart request (within 2 min)' -Passed $wentDown -RawValue ([pscustomobject]@{ went_down = $wentDown; observed_at = (Get-Date).ToUniversalTime().ToString('o') })
    }
    else {
        Add-Assertion -Name 'Restart is gated on successful integration updates' -Passed $false -RawValue 'Restart not requested because a precondition or update assertion failed.'
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
}
$evidencePath = Join-Path $EvidenceDir ("{0}-{1}.json" -f $ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

if ($failed.Count -gt 0) {
    Write-Host ("{0} FAIL ({1} failed of {2}; evidence: {3})" -f $ScriptName, $failed.Count, $Assertions.Count, $evidencePath)
    exit 1
}
Write-Host ("{0} PASS ({1} assertions; evidence: {2})" -f $ScriptName, $Assertions.Count, $evidencePath)
exit 0
