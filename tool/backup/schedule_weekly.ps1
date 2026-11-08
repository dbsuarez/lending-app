param(
  [string]$CopyTo = 'E:\LendingManagerBackups',
  [string]$Day = 'Sunday',
  [string]$At = '09:00',
  [switch]$Remove
)
# Registers (or removes) the weekly backup in Windows Task Scheduler.
# Runs as the current user; if the PC was off at that time it runs at the
# next start-up. Results: backups\backup-log.txt.
$name = 'Lending Manager weekly backup'
if ($Remove) {
  Unregister-ScheduledTask -TaskName $name -Confirm:$false
  "Removed '$name'."
  return
}
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$node = (Get-Command node -ErrorAction Stop).Source
$script = Join-Path $repo 'tool\backup\backup.mjs'
$argLine = "`"$script`""
if ($CopyTo) { $argLine += " --copy-to `"$CopyTo`"" }
$action = New-ScheduledTaskAction -Execute $node -Argument $argLine -WorkingDirectory $repo
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings `
  -Description 'Backs up Lending Manager, checks it, rehearses a restore. Log: backups\backup-log.txt' -Force | Out-Null
"Scheduled '$name': every $Day at $At, copy to $CopyTo."
