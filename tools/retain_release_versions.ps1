param([Parameter(Mandatory=$true)][string[]]$Keep)
$ErrorActionPreference='Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$distRoot = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'dist')).Path
$checkpointRoot = Join-Path (Split-Path -Parent $repoRoot) ('_testenv\release-retention\'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $checkpointRoot | Out-Null
foreach ($name in $Keep) {
    if ($name -match '[\\/]' -or -not (Test-Path -LiteralPath (Join-Path $distRoot $name) -PathType Container)) { throw "Invalid retained release: $name" }
}
$candidates = @(Get-ChildItem -LiteralPath $distRoot -Directory | Where-Object { $_.Name -notin $Keep -and $_.Name -match '^(a0_\d+(_play)?|retail\d*|v3_[a-z0-9_]+|windows|chapter_one_\d+\.\d+\.\d+_\d{8})$' })
$report = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $candidates) {
    $targetPath = (Resolve-Path -LiteralPath $entry.FullName).Path
    if (-not $targetPath.StartsWith($distRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "Outside dist: $targetPath" }
    $all = @(Get-ChildItem -LiteralPath $targetPath -Recurse -Force)
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($all | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) { throw "Reparse point: $targetPath" }
    foreach ($saveFile in ($all | Where-Object { -not $_.PSIsContainer -and ($_.Name -like 'savegame*.json' -or $_.Name -eq 'settings.cfg') })) {
        $relative = $saveFile.FullName.Substring($distRoot.Length+1)
        $destination = Join-Path $checkpointRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $saveFile.FullName -Destination $destination
        if ((Get-FileHash -LiteralPath $saveFile.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw 'Save checkpoint mismatch' }
    }
    $bytes = ($all | Where-Object { -not $_.PSIsContainer } | Measure-Object Length -Sum).Sum
    Remove-Item -LiteralPath $targetPath -Recurse -Force
    $report.Add([PSCustomObject]@{path=$targetPath;bytes=$bytes;kind='obsolete exported build'})
}
foreach ($entry in (Get-ChildItem -LiteralPath $distRoot -File -Filter '*.zip')) {
    if ($entry.Name -notlike '星丘残响_*') { continue }
    $retain = $false
    foreach ($name in $Keep) {
        if ($name -match 'chapter_one_(\d+\.\d+\.\d+)_(\d{8})' -and $entry.Name.Contains($Matches[1]+'_'+$Matches[2])) { $retain=$true }
    }
    if ($retain) { continue }
    $targetPath=(Resolve-Path -LiteralPath $entry.FullName).Path
    if ((Split-Path -Parent $targetPath) -ne $distRoot -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid archive target' }
    $bytes=$entry.Length
    Remove-Item -LiteralPath $targetPath -Force
    $report.Add([PSCustomObject]@{path=$targetPath;bytes=$bytes;kind='obsolete release zip'})
}
$result=[PSCustomObject]@{kept=$Keep;checkpoint=$checkpointRoot;deleted=$report;reclaimedBytes=($report | Measure-Object bytes -Sum).Sum}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $checkpointRoot 'retention_report.json') -Encoding utf8
$result | Select-Object kept,checkpoint,reclaimedBytes | ConvertTo-Json
