[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [switch]$NoBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Step([string]$Message) {
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Fail([int]$Code, [string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit $Code
}

function Decode-Bytes([byte[]]$Bytes) {
    if ($Bytes.Length -eq 0) {
        return @("", "empty")
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
        return @($text, "utf16-le-bom")
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        $text = [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2)
        return @($text, "utf16-be-bom")
    }

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        $text = [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
        return @($text, "utf8-bom")
    }

    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $utf8Strict.GetString($Bytes)
        return @($text, "utf8")
    } catch {
    }

    # Excel's "ANSI" save on Korean Windows is usually CP949.
    $cp949 = [System.Text.Encoding]::GetEncoding(949)
    $text = $cp949.GetString($Bytes)
    return @($text, "cp949/ansi")
}

function Ensure-NoLeadingBom([string]$Text) {
    if ($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF) {
        return $Text.Substring(1)
    }
    return $Text
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Step "Convert TSV encoding to UTF-8 (without BOM)"

foreach ($input in $Path) {
    $resolved = Resolve-Path -LiteralPath $input -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-Host "[WARN] File not found: $input" -ForegroundColor Yellow
        continue
    }

    $targetPath = [string]$resolved.Path
    if ([System.IO.Path]::GetExtension($targetPath).ToLowerInvariant() -ne ".tsv") {
        Write-Host "[WARN] Not a .tsv file: $targetPath" -ForegroundColor Yellow
    }

    $bytes = [System.IO.File]::ReadAllBytes($targetPath)
    $decoded = Decode-Bytes $bytes
    $text = Ensure-NoLeadingBom([string]$decoded[0])
    $sourceEncoding = [string]$decoded[1]

    if (-not $NoBackup) {
        $backupPath = "{0}.bak.{1}" -f $targetPath, (Get-Date -Format "yyyyMMdd_HHmmss")
        Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
        Write-Host ("  Backup: {0}" -f $backupPath)
    }

    [System.IO.File]::WriteAllText($targetPath, $text, $utf8NoBom)
    Write-Host ("[OK] {0} ({1} -> utf8-nobom)" -f $targetPath, $sourceEncoding)
}

Write-Host ""
Write-Host "convert_tsv_to_utf8.ps1 complete" -ForegroundColor Green
exit 0
