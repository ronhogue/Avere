$binDirectory = "C:\Users\Public\Downloads"
Set-Location -Path $binDirectory

$scriptFile = "C:\AzureData\functions.ps1"
Copy-Item -Path "C:\AzureData\CustomData.bin" -Destination $scriptFile
. $scriptFile

SetFileSystems $binDirectory '${jsonencode(fileSystems)}'

EnableFarmClient

if ("${terminateNotification.enable}" -eq $true) {
  $taskName = "AAA Terminate Event Handler"
  $taskInterval = New-TimeSpan -Minutes 1
  $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Unrestricted -File C:\AzureData\terminate.ps1"
  $taskTrigger = New-ScheduledTaskTrigger -RepetitionInterval $taskInterval -At $(Get-Date) -Once
  Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -User System -Force
}

if ("${activeDirectory.enable}" -eq $true) {
  Retry 5 10 {
    JoinActiveDirectory ${activeDirectory.domainName} ${activeDirectory.domainServerName} "${activeDirectory.orgUnitPath}" ${activeDirectory.adminUsername} ${activeDirectory.adminPassword}
  }
}
