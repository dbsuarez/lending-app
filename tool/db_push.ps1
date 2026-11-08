param([switch]$Apply)
# Push supabase/migrations to production over the pooler (the linked CLI
# returns HTTP 403 for this account). Without -Apply it is a dry run.
#
# The database password is read from docs/notes_la (gitignored) at run time,
# never printed, and scrubbed from the CLI output.
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$line = Get-Content docs\notes_la -ErrorAction Stop |
  Where-Object { $_ -match '^\s*db pass:\s*(.+)$' } | Select-Object -First 1
if (-not $line) { throw 'db pass not found in docs/notes_la' }
$pw = ($line -replace '^\s*db pass:\s*', '').Trim()
$enc = [Uri]::EscapeDataString($pw)
$url = "postgresql://postgres.bfrifjiqqlziejocleax:$enc@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres"
$cliArgs = @('--yes', 'supabase', 'db', 'push', '--db-url', $url)
if ($Apply) { $cliArgs += '--yes' } else { $cliArgs += '--dry-run' }
npx @cliArgs 2>&1 | ForEach-Object { "$_".Replace($pw, '***').Replace($enc, '***') } | Select-Object -Last 15
$pw = $null; $enc = $null; $url = $null
