param(
  [Parameter(Mandatory = $true)][string]$File,
  [switch]$ReadOnly,
  # Required for statements that change data (the CLI asks for consent).
  [switch]$Apply
)
# Runs a SQL file against production over the pooler (for one-off, reviewed
# data fixes; schema changes go through migrations and db_push.ps1).
#
# The database password is read from docs/notes_la (gitignored) at run time,
# never printed, and scrubbed from the CLI output. Take a backup first:
#   node tool/backup/backup.mjs
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$line = Get-Content docs\notes_la -ErrorAction Stop |
  Where-Object { $_ -match '^\s*db pass:\s*(.+)$' } | Select-Object -First 1
if (-not $line) { throw 'db pass not found in docs/notes_la' }
$pw = ($line -replace '^\s*db pass:\s*', '').Trim()
$enc = [Uri]::EscapeDataString($pw)
$url = "postgresql://postgres.bfrifjiqqlziejocleax:$enc@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres"
$cliArgs = @('--yes', 'supabase', 'db', 'query', "--remote=$url", '--file', $File)
if ($ReadOnly) { $cliArgs += '--read-only' }
elseif ($Apply) { $cliArgs += '--yes' }
npx @cliArgs 2>&1 | ForEach-Object { "$_".Replace($pw, '***').Replace($enc, '***') }
$pw = $null; $enc = $null; $url = $null
