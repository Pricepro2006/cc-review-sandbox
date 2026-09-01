param([string]$EvidenceDir = "C:\Users\mrshr\tmp\ha-update")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HaRest = 'C:\Users\mrshr\Documents\homelab-tools\ha-rest.ps1'
$HaWs = 'C:\Users\mrshr\Documents\homelab-tools\ha-ws.ps1'
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$StartedAt = Get-Date
$Assertions = New-Object System.Collections.ArrayList
$DashboardDumps = New-Object System.Collections.ArrayList

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

function Invoke-HaWsJson {
    param([string]$MsgJson, [string]$OutFile)
    $jsonText = & $script:HaWs -MsgJson $MsgJson -OutFile $OutFile
    return ($jsonText | ConvertFrom-Json)
}

function Get-WsResult {
    param([object]$Response)
    if ($null -ne $Response.PSObject.Properties['result']) { return $Response.result }
    return $Response
}

function Test-WsSuccess {
    param([object]$Response)
    if ($null -ne $Response.PSObject.Properties['success']) { return $Response.success -eq $true }
    return $true
}

function Get-SafeDashboardName {
    param([string]$UrlPath)
    if ([string]::IsNullOrWhiteSpace($UrlPath)) { return 'default' }
    return ($UrlPath -replace '[^A-Za-z0-9._-]', '_')
}

function Get-DashboardUrlPaths {
    param([object]$DashboardListResponse)
    $paths = New-Object System.Collections.ArrayList
    [void]$paths.Add('')
    foreach ($dashboard in @(Get-WsResult -Response $DashboardListResponse)) {
        if ($null -ne $dashboard.PSObject.Properties['url_path'] -and -not [string]::IsNullOrWhiteSpace([string]$dashboard.url_path)) {
            if (@($paths | Where-Object { [string]$_ -eq [string]$dashboard.url_path }).Count -eq 0) {
                [void]$paths.Add([string]$dashboard.url_path)
            }
        }
    }
    return @($paths)
}

function Dump-Dashboards {
    param([ValidateSet('before', 'after')][string]$Stage)

    $listFile = Join-Path $script:EvidenceDir ("lovelace-dashboards-{0}.json" -f $Stage)
    $listResponse = Invoke-HaWsJson -MsgJson '{"type":"lovelace/dashboards/list"}' -OutFile $listFile
    Add-Assertion -Name ("Lovelace dashboard list dumped ({0})" -f $Stage) -Passed (Test-WsSuccess -Response $listResponse) -RawValue ([pscustomobject]@{ file = $listFile; response = $listResponse })

    foreach ($urlPath in @(Get-DashboardUrlPaths -DashboardListResponse $listResponse)) {
        $safeName = Get-SafeDashboardName -UrlPath $urlPath
        $outFile = Join-Path $script:EvidenceDir ("lovelace-{0}-{1}.json" -f $safeName, $Stage)
        if ([string]::IsNullOrWhiteSpace($urlPath)) {
            $message = '{"type":"lovelace/config","force":true}'
        }
        else {
            $message = @{ type = 'lovelace/config'; url_path = $urlPath; force = $true } | ConvertTo-Json -Compress
        }
        $configResponse = Invoke-HaWsJson -MsgJson $message -OutFile $outFile
        Add-Assertion -Name ("Lovelace dashboard dumped ({0}): {1}" -f $Stage, $safeName) -Passed (Test-WsSuccess -Response $configResponse) -RawValue ([pscustomobject]@{ url_path = $urlPath; file = $outFile; response = $configResponse })

        $existing = @($script:DashboardDumps | Where-Object { $_.name -eq $safeName }) | Select-Object -First 1
        if ($null -eq $existing) {
            $existing = [pscustomobject]@{ name = $safeName; url_path = $urlPath; before_file = $null; after_file = $null }
            [void]$script:DashboardDumps.Add($existing)
        }
        if ($Stage -eq 'before') { $existing.before_file = $outFile } else { $existing.after_file = $outFile }
    }
}

try {
    # The before dump is deliberately the first remote operation in this script.
    Dump-Dashboards -Stage 'before'

    if (@($Assertions | Where-Object { -not $_.passed }).Count -eq 0) {
        $target = Invoke-HaJson -Method GET -Path '/api/states/update.advanced_camera_card_update'
        $versionsMatch = [string]$target.attributes.installed_version -eq 'v7.27.4' -and
            [string]$target.attributes.latest_version -eq 'v8.0.1' -and
            $target.attributes.in_progress -ne $true
        Add-Assertion -Name 'Advanced Camera Card versions match the approved update' -Passed $versionsMatch -RawValue $target
    }

    if (@($Assertions | Where-Object { -not $_.passed }).Count -eq 0) {
        $body = @{ entity_id = 'update.advanced_camera_card_update'; backup = $false } | ConvertTo-Json -Compress
        $installResponse = Invoke-HaJson -Method POST -Path '/api/services/update/install' -BodyJson $body
        Add-Assertion -Name 'Advanced Camera Card install service call completed' -Passed $true -RawValue $installResponse

        $deadline = (Get-Date).AddMinutes(10)
        $completed = $false
        $lastState = $null
        do {
            Start-Sleep -Seconds 5
            $lastState = Invoke-HaJson -Method GET -Path '/api/states/update.advanced_camera_card_update'
            $completed = $lastState.attributes.in_progress -ne $true -and
                [string]$lastState.attributes.installed_version -eq 'v8.0.1'
            if ($completed) { break }
        } while ((Get-Date) -lt $deadline)
        Add-Assertion -Name 'Advanced Camera Card reached v8.0.1 within 10 minutes' -Passed $completed -RawValue $lastState
    }

    if (@($Assertions | Where-Object { -not $_.passed }).Count -eq 0) {
        Dump-Dashboards -Stage 'after'
        $missingPairs = @($DashboardDumps | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.before_file) -or [string]::IsNullOrWhiteSpace([string]$_.after_file)
        })
        Add-Assertion -Name 'Every dashboard has paired before and after dumps' -Passed ($missingPairs.Count -eq 0) -RawValue $DashboardDumps
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
    dashboard_dumps = $DashboardDumps
}
$evidencePath = Join-Path $EvidenceDir ("{0}-{1}.json" -f $ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

if ($failed.Count -gt 0) {
    Write-Host ("{0} FAIL ({1} failed of {2}; evidence: {3})" -f $ScriptName, $failed.Count, $Assertions.Count, $evidencePath)
    exit 1
}
Write-Host ("{0} PASS ({1} assertions; evidence: {2})" -f $ScriptName, $Assertions.Count, $evidencePath)
exit 0
