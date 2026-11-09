# Production Android release APK. See docs/DEPLOYMENT.md.
#
#   powershell -ExecutionPolicy Bypass -File tool/build_apk.ps1 [-Install]
#
# Same public-only defines as tool/build_web.ps1 (never --dart-define-from-file
# =.env, which may embed dev login credentials). arm64 only to keep the build
# small. -Install replaces the app on the connected phone with `adb install -r`,
# which keeps its data; it stops instead of uninstalling if signatures differ.
param([switch]$Install)
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

$ErrorActionPreference = 'Continue'
# Icon tree-shaking corrupts some glyphs (blank icons); ship the full font.
& $dart "--packages=$flutterPackages" $flutterSnapshot build apk --release --target-platform android-arm64 --no-tree-shake-icons `
  "--dart-define=SUPABASE_URL=$($envMap.SUPABASE_URL)" `
  "--dart-define=SUPABASE_ANON_KEY=$($envMap.SUPABASE_ANON_KEY)" `
  "--dart-define=APP_ENV=production" `
  "--dart-define=PUBLIC_APP_URL=https://lending-manager-ph.web.app" `
  "--dart-define=BUILD_ID=$buildId" 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed ($LASTEXITCODE)" }
$ErrorActionPreference = 'Stop'

$apk = 'build\app\outputs\flutter-apk\app-release.apk'
# Credential scan: the compiled Dart snapshot (libapp.so) must not contain
# dev login keys or values.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $apk))
try {
  $needles = @('DEV_LOGIN_EMAIL', 'DEV_LOGIN_PASSWORD')
  foreach ($k in $needles) { if ($envMap[$k]) { $needles += $envMap[$k] } }
  $hits = 0; $foundBuildId = $false
  foreach ($entry in $zip.Entries | Where-Object { $_.FullName -like 'lib/*/libapp.so' }) {
    $ms = New-Object IO.MemoryStream; $s = $entry.Open(); $s.CopyTo($ms); $s.Dispose()
    $text = [Text.Encoding]::GetEncoding(28591).GetString($ms.ToArray())
    for ($i = 0; $i -lt $needles.Count; $i++) { if ($text.Contains($needles[$i])) { $hits++; "LEAK: needle #$i" } }
    if ($text.Contains($buildId)) { $foundBuildId = $true }
  }
} finally { $zip.Dispose() }
"credential scan hits: $hits; BUILD_ID embedded: $foundBuildId"
if ($hits -gt 0) { throw 'Credential scan failed; do not install' }
"APK: $apk ($([math]::Round((Get-Item $apk).Length / 1MB, 1)) MB)"

if ($Install) {
  $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  $ErrorActionPreference = 'Continue'
  $result = & $adb install -r $apk 2>&1 | ForEach-Object { "$_" }
  $result | Select-Object -Last 1
  if ($result -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
    throw 'Signature differs from the installed app. Not uninstalling (it would erase app data); ask the owner.'
  }
}
