param([string]$EvidenceDir = "C:\Users\mrshr\tmp\ha-update")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HaWs = 'C:\Users\mrshr\Documents\homelab-tools\ha-ws.ps1'
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$StartedAt = Get-Date
$Assertions = New-Object System.Collections.ArrayList
$Changes = New-Object System.Collections.ArrayList

if (-not (Test-Path -LiteralPath $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

function Add-Assertion {
    param([string]$Name, [bool]$Passed, [object]$RawValue)
    [void]$script:Assertions.Add([pscustomobject]@{ name = $Name; passed = $Passed; raw_value = $RawValue })
}

function Add-Change {
    param([string]$Dashboard, [string]$Path, [object]$Before, [object]$After)
    [void]$script:Changes.Add([pscustomobject]@{ dashboard = $Dashboard; path = $Path; before = $Before; after = $After })
}

function Compare-JsonValue {
    param([string]$Dashboard, [object]$Before, [object]$After, [string]$Path)

    if ($null -eq $Before -or $null -eq $After) {
        if (-not ($null -eq $Before -and $null -eq $After)) { Add-Change -Dashboard $Dashboard -Path $Path -Before $Before -After $After }
        return
    }

    $beforeIsObject = $Before -is [pscustomobject]
    $afterIsObject = $After -is [pscustomobject]
    if ($beforeIsObject -and $afterIsObject) {
        $names = @(@($Before.PSObject.Properties.Name) + @($After.PSObject.Properties.Name) | Sort-Object -Unique)
        foreach ($name in $names) {
            $beforeProperty = $Before.PSObject.Properties[$name]
            $afterProperty = $After.PSObject.Properties[$name]
            $childPath = "{0}.{1}" -f $Path, $name
            if ($null -eq $beforeProperty) {
                Add-Change -Dashboard $Dashboard -Path $childPath -Before '<missing>' -After $afterProperty.Value
            }
            elseif ($null -eq $afterProperty) {
                Add-Change -Dashboard $Dashboard -Path $childPath -Before $beforeProperty.Value -After '<missing>'
            }
            else {
                Compare-JsonValue -Dashboard $Dashboard -Before $beforeProperty.Value -After $afterProperty.Value -Path $childPath
            }
        }
        return
    }

    $beforeIsArray = $Before -is [System.Array]
    $afterIsArray = $After -is [System.Array]
    if ($beforeIsArray -and $afterIsArray) {
        $max = [math]::Max($Before.Count, $After.Count)
        for ($index = 0; $index -lt $max; $index++) {
            $childPath = "{0}[{1}]" -f $Path, $index
            if ($index -ge $Before.Count) { Add-Change -Dashboard $Dashboard -Path $childPath -Before '<missing>' -After $After[$index] }
            elseif ($index -ge $After.Count) { Add-Change -Dashboard $Dashboard -Path $childPath -Before $Before[$index] -After '<missing>' }
            else { Compare-JsonValue -Dashboard $Dashboard -Before $Before[$index] -After $After[$index] -Path $childPath }
        }
        return
    }

    $beforeJson = $Before | ConvertTo-Json -Depth 20 -Compress
    $afterJson = $After | ConvertTo-Json -Depth 20 -Compress
    if ($beforeJson -cne $afterJson) { Add-Change -Dashboard $Dashboard -Path $Path -Before $Before -After $After }
}

function Get-WsResult {
    param([object]$Response)
    if ($null -ne $Response.PSObject.Properties['result']) { return $Response.result }
    return $Response
}

try {
    $afterFiles = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter 'lovelace-*-after.json' -File | Where-Object { $_.Name -ne 'lovelace-dashboards-after.json' } | Sort-Object Name)
    $beforeFiles = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter 'lovelace-*-before.json' -File | Where-Object { $_.Name -ne 'lovelace-dashboards-before.json' } | Sort-Object Name)
    Add-Assertion -Name 'At least one Lovelace after-dump exists' -Passed ($afterFiles.Count -gt 0) -RawValue $afterFiles.FullName

    $beforeKeys = @($beforeFiles | ForEach-Object { $_.Name -replace '-before\.json$', '' })
    $afterKeys = @($afterFiles | ForEach-Object { $_.Name -replace '-after\.json$', '' })
    $unpairedKeys = @(Compare-Object -ReferenceObject $beforeKeys -DifferenceObject $afterKeys)
    Add-Assertion -Name 'Before and after dashboard dump sets match' -Passed ($unpairedKeys.Count -eq 0) -RawValue ([pscustomobject]@{ before = $beforeKeys; after = $afterKeys; differences = $unpairedKeys })

    $upgradeFailures = New-Object System.Collections.ArrayList
    foreach ($afterFile in $afterFiles) {
        $failureHits = @(Select-String -LiteralPath $afterFile.FullName -SimpleMatch '__UPGRADE_FAILURE__')
        if ($failureHits.Count -gt 0) {
            [void]$upgradeFailures.Add([pscustomobject]@{ file = $afterFile.FullName; matches = $failureHits.Line })
        }

        $beforeName = $afterFile.Name -replace '-after\.json$', '-before.json'
        $beforePath = Join-Path $EvidenceDir $beforeName
        $pairExists = Test-Path -LiteralPath $beforePath
        Add-Assertion -Name ("Before-dump exists for {0}" -f $afterFile.Name) -Passed $pairExists -RawValue $beforePath
        if ($pairExists) {
            $beforeJson = Get-Content -LiteralPath $beforePath -Raw | ConvertFrom-Json
            $afterJson = Get-Content -LiteralPath $afterFile.FullName -Raw | ConvertFrom-Json
            $beforeConfig = Get-WsResult -Response $beforeJson
            $afterConfig = Get-WsResult -Response $afterJson
            $dashboardName = $afterFile.BaseName -replace '^lovelace-', '' -replace '-after$', ''
            Compare-JsonValue -Dashboard $dashboardName -Before $beforeConfig -After $afterConfig -Path '$'
        }
    }
    Add-Assertion -Name 'No dashboard after-dump contains __UPGRADE_FAILURE__' -Passed ($upgradeFailures.Count -eq 0) -RawValue $upgradeFailures

    foreach ($change in $Changes) {
        Write-Host ("CHANGE {0} {1}" -f $change.dashboard, $change.path)
        Write-Host ("  BEFORE: {0}" -f ($change.before | ConvertTo-Json -Depth 20 -Compress))
        Write-Host ("  AFTER:  {0}" -f ($change.after | ConvertTo-Json -Depth 20 -Compress))
    }

    $resourceFile = Join-Path $EvidenceDir 'lovelace-resources.json'
    # ha-ws.ps1 emits only via Write-Host and writes the raw response to -OutFile; read it back from the file.
    if (Test-Path -LiteralPath $resourceFile) { Remove-Item -LiteralPath $resourceFile -Force }
    & $HaWs -MsgJson '{"type":"lovelace/resources"}' -OutFile $resourceFile | Out-Null
    if (-not (Test-Path -LiteralPath $resourceFile)) { throw "ha-ws.ps1 did not write $resourceFile" }
    $resourceResponse = Get-Content -LiteralPath $resourceFile -Raw | ConvertFrom-Json
    $resources = @(Get-WsResult -Response $resourceResponse)
    $matchingResources = @($resources | Where-Object {
        $url = [string]$_.url
        $url -match '(?i)advanced-camera-card' -and ($url -match 'v8\.0\.1' -or $url -match '(?i)/hacsfiles/')
    })
    Add-Assertion -Name 'Advanced Camera Card resource points to v8.0.1 or a HACS files path' -Passed ($matchingResources.Count -gt 0) -RawValue ([pscustomobject]@{ matching = $matchingResources; all_resources = $resources; file = $resourceFile })

    try {
        $lovelaceResponse = Invoke-WebRequest -Uri 'http://10.0.0.50:8123/lovelace' -UseBasicParsing -TimeoutSec 30
        Add-Assertion -Name 'Local Lovelace endpoint returns HTTP 200' -Passed ([int]$lovelaceResponse.StatusCode -eq 200) -RawValue ([pscustomobject]@{ status_code = $lovelaceResponse.StatusCode; status_description = $lovelaceResponse.StatusDescription })
    }
    catch {
        Add-Assertion -Name 'Local Lovelace endpoint returns HTTP 200' -Passed $false -RawValue ($_ | Out-String)
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
    changed_blocks = $Changes
}
$evidencePath = Join-Path $EvidenceDir ("{0}-{1}.json" -f $ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

if ($failed.Count -gt 0) {
    Write-Host ("{0} FAIL ({1} failed of {2}; evidence: {3})" -f $ScriptName, $failed.Count, $Assertions.Count, $evidencePath)
    exit 1
}
Write-Host ("{0} PASS ({1} assertions, {2} changed blocks; evidence: {3})" -f $ScriptName, $Assertions.Count, $Changes.Count, $evidencePath)
exit 0
