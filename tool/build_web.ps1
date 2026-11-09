# Production web build for Firebase Hosting. See docs/DEPLOYMENT.md.
#
#   powershell -ExecutionPolicy Bypass -File tool/build_web.ps1
#
# Reads SUPABASE_URL and SUPABASE_ANON_KEY from .env (never echoes them),
# stamps BUILD_ID in Asia/Taipei time, builds with only the public
# dart-defines, injects the same public values into build/web/status.html
# (the plain-HTML customer status page), then fails if any development
# credential key or value appears anywhere under build/web.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$sdkLink = Get-Item '.fvm\flutter_sdk' -ErrorAction Stop
$sdk = if ($sdkLink.Target) { $sdkLink.Target[0] } else { $sdkLink.FullName }
$dart = Join-Path $sdk 'bin\cache\dart-sdk\bin\dart.exe'
$flutterPackages = Join-Path $sdk 'packages\flutter_tools\.dart_tool\package_config.json'
$flutterSnapshot = Join-Path $sdk 'bin\cache\flutter_tools.snapshot'

$envMap = @{}
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$' -and -not $envMap.ContainsKey($matches[1])) {
    $envMap[$matches[1]] = $matches[2].Trim().Trim('"')
  }
}
if (-not $envMap.SUPABASE_URL -or -not $envMap.SUPABASE_ANON_KEY) {
  throw 'Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env'
}

$tz = [TimeZoneInfo]::FindSystemTimeZoneById('Taipei Standard Time')
$buildId = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz).ToString('yyyyMMdd_HHmm')
"BUILD_ID=$buildId"

# flutter writes notices to stderr; don't treat them as failures.
$ErrorActionPreference = 'Continue'
# --pwa-strategy=none: no offline cache, so a deploy shows on the next reload
# (the default cache kept serving the previous version until a 2nd reload).
# Icon tree-shaking corrupts some glyphs (blank icons); ship the full font.
& $dart "--packages=$flutterPackages" $flutterSnapshot build web --release --pwa-strategy=none --no-tree-shake-icons `
  "--dart-define=SUPABASE_URL=$($envMap.SUPABASE_URL)" `
  "--dart-define=SUPABASE_ANON_KEY=$($envMap.SUPABASE_ANON_KEY)" `
  "--dart-define=APP_ENV=production" `
  "--dart-define=PUBLIC_APP_URL=https://lending-manager-ph.web.app" `
  "--dart-define=BUILD_ID=$buildId" 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }
$ErrorActionPreference = 'Stop'

# Replace the (empty) service worker with one that removes old ones and their
# stale caches from browsers that visited earlier versions.
Copy-Item web\sw_kill_switch.js build\web\flutter_service_worker.js -Force
Remove-Item build\web\sw_kill_switch.js -ErrorAction SilentlyContinue
# Version for the once-per-version fresh fetch of fonts in flutter_bootstrap.js.
$boot = 'build\web\flutter_bootstrap.js'
$bootText = [IO.File]::ReadAllText($boot)
if (-not $bootText.Contains('__BUILD_ID__')) { throw "$boot is missing __BUILD_ID__" }
[IO.File]::WriteAllText($boot, $bootText.Replace('__BUILD_ID__', $buildId), (New-Object Text.UTF8Encoding $false))

# The running app compares its build with this file to offer updates.
[IO.File]::WriteAllText('build\web\app_build.json', "{`"build_id`":`"$buildId`"}", (New-Object Text.UTF8Encoding $false))

$statusPage = 'build\web\status.html'
$html = [IO.File]::ReadAllText($statusPage)
if (-not $html.Contains('__SUPABASE_URL__') -or -not $html.Contains('__SUPABASE_ANON_KEY__')) {
  throw "$statusPage is missing its config placeholders"
}
$html = $html.Replace('__SUPABASE_URL__', $envMap.SUPABASE_URL).Replace('__SUPABASE_ANON_KEY__', $envMap.SUPABASE_ANON_KEY)
[IO.File]::WriteAllText($statusPage, $html, (New-Object Text.UTF8Encoding $false))

$needles = @('DEV_LOGIN_EMAIL', 'DEV_LOGIN_PASSWORD')
foreach ($k in 'DEV_LOGIN_EMAIL', 'DEV_LOGIN_PASSWORD') { if ($envMap[$k]) { $needles += $envMap[$k] } }
$hits = 0
Get-ChildItem build\web -Recurse -File | ForEach-Object {
  $text = [IO.File]::ReadAllText($_.FullName)
  for ($i = 0; $i -lt $needles.Count; $i++) {
    if ($text.Contains($needles[$i])) { $hits++; "LEAK: needle #$i in $($_.FullName)" }
  }
}
"credential scan hits: $hits"
if ($hits -gt 0) { throw 'Credential scan failed; do not deploy' }
if (-not ([IO.File]::ReadAllText('build\web\main.dart.js')).Contains($buildId)) {
  throw 'BUILD_ID missing from main.dart.js'
}
"OK: build/web ready for deploy (BUILD_ID=$buildId)"
