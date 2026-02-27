[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$InputTsv = "",
    [string]$OutputTsv = "",
    [switch]$NoBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toggleScript = Join-Path $PSScriptRoot "toggle_review_subtitle_ids.ps1"
if (-not (Test-Path $toggleScript)) {
    Write-Host "[ERROR] Required file not found: $toggleScript" -ForegroundColor Red
    exit 10
}

$args = @{
    Mode = "add"
}
if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $args["WorkspaceRoot"] = $WorkspaceRoot }
if (-not [string]::IsNullOrWhiteSpace($InputTsv)) { $args["InputTsv"] = $InputTsv }
if (-not [string]::IsNullOrWhiteSpace($OutputTsv)) { $args["OutputTsv"] = $OutputTsv }
if ($NoBackup) { $args["NoBackup"] = $true }

& $toggleScript @args
exit $LASTEXITCODE
