$ErrorActionPreference = "Stop"

$Bucket = "digients-recordings-sg"
$Region = "ap-southeast-1"
$FullPrefix = "uploads/client-data-sample-plain"
$SmallerPrefix = "uploads/smaller-sample"
$Prefix = $FullPrefix
$RemoteName = "aws-s3"
$FullDefaultDestDir = Join-Path (Join-Path $HOME "Downloads") "client-data-sample-plain"
$SmallerDefaultDestDir = Join-Path (Join-Path $HOME "Downloads") "smaller-sample"
$DefaultDestDir = $FullDefaultDestDir
$DatasetTitle = "Data Sample Plain"
$DatasetSizeMessage = "Dataset size is about 88GB. Make sure the destination disk has enough space."
$RecommendedGiB = 100
$Transfers = "4"
$Checkers = "16"
$MultiThreadStreams = "4"
$MultiThreadCutoff = "256M"
$Script:TempDir = $null
$Script:ConfigFile = $null
$Script:ActiveProcess = $null

function Show-Usage {
@"
Data Sample Plain preview/download helper for AWS S3.

This script is interactive:
  1. Enter AWS Access Key ID and AWS Secret Access Key.
  2. Choose Preview or Download in the terminal menu.

The data is available in AWS S3:
  Provider: AWS S3
  Region: ap-southeast-1
  Bucket: digients-recordings-sg
  Prefix: uploads/client-data-sample-plain/
  S3 URI: s3://digients-recordings-sg/uploads/client-data-sample-plain/

Smaller sample mirror:
  Prefix: uploads/smaller-sample/
  S3 URI: s3://digients-recordings-sg/uploads/smaller-sample/

At startup the script asks whether to download the smaller sample with the
scene/task_category L2 directory structure. The default answer is no, which
downloads the full dataset.

AWS Console:
  https://ap-southeast-1.console.aws.amazon.com/s3/buckets/digients-recordings-sg?prefix=uploads%2Fclient-data-sample-plain%2F&region=ap-southeast-1&showversions=false&tab=objects

Usage:
  powershell -ExecutionPolicy Bypass -File .\download_data_sample_aws.ps1
  powershell -ExecutionPolicy Bypass -File .\download_data_sample_aws.ps1 -Help

Notes:
  - Requires rclone.
  - Preview only lists metadata and does not download the dataset.
  - Download preserves the dataset directory structure under the chosen local directory.
  - Re-running Download resumes/skips files that are already complete.
  - AWS IAM username/password cannot be used by rclone/S3; use an access key.

If rclone is not installed:
  Windows: winget install Rclone.Rclone
  Or use the official docs: https://rclone.org/install/
"@
}

function ConvertTo-PlainText {
  param([Parameter(Mandatory = $true)][System.Security.SecureString]$SecureString)

  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
  try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Require-Command {
  param([Parameter(Mandatory = $true)][string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Write-Host "Error: '$Name' is not installed or not in PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install rclone first:"
    Write-Host "  Windows: winget install Rclone.Rclone"
    Write-Host "  Official docs: https://rclone.org/install/"
    Write-Host ""
    Write-Host "After installing rclone, run this script again:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\download_data_sample_aws.ps1"
    exit 1
  }
}

function Resolve-UserPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ($Path -eq "~") {
    return $HOME
  }
  if ($Path.StartsWith("~/") -or $Path.StartsWith("~\")) {
    return (Join-Path $HOME $Path.Substring(2))
  }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path (Get-Location) $Path)
}

function Cleanup {
  if ($Script:TempDir -and (Test-Path -LiteralPath $Script:TempDir)) {
    Remove-Item -LiteralPath $Script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Stop-ActiveRclone {
  if ($Script:ActiveProcess -and -not $Script:ActiveProcess.HasExited) {
    try {
      $Script:ActiveProcess.Kill()
      $Script:ActiveProcess.WaitForExit()
    }
    catch {
      # Best effort on interrupt.
    }
  }
}

function Quote-ProcessArgument {
  param([Parameter(Mandatory = $true)][string]$Argument)

  if ($Argument.Length -eq 0) {
    return '""'
  }
  if ($Argument -notmatch '[\s"]') {
    return $Argument
  }

  $result = '"'
  $backslashes = 0
  foreach ($char in $Argument.ToCharArray()) {
    if ($char -eq '\') {
      $backslashes += 1
      continue
    }
    if ($char -eq '"') {
      $result += ('\' * (($backslashes * 2) + 1)) + '"'
      $backslashes = 0
      continue
    }
    if ($backslashes -gt 0) {
      $result += '\' * $backslashes
      $backslashes = 0
    }
    $result += $char
  }
  if ($backslashes -gt 0) {
    $result += '\' * ($backslashes * 2)
  }
  $result += '"'
  return $result
}

function Invoke-Rclone {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [string]$OutputFile
  )

  $allArgs = @("--config", $Script:ConfigFile) + $Arguments
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = "rclone"
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = -not [string]::IsNullOrWhiteSpace($OutputFile)

  $argumentListProperty = $startInfo.GetType().GetProperty("ArgumentList")
  if ($argumentListProperty -ne $null) {
    foreach ($arg in $allArgs) {
      [void]$startInfo.ArgumentList.Add($arg)
    }
  }
  else {
    $startInfo.Arguments = (($allArgs | ForEach-Object { Quote-ProcessArgument $_ }) -join " ")
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $Script:ActiveProcess = $process
  try {
    $stdout = $null
    if ($OutputFile) {
      $stdout = $process.StandardOutput.ReadToEnd()
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
      throw "rclone exited with status $($process.ExitCode): $($Arguments -join ' ')"
    }
    if ($OutputFile) {
      Set-Content -LiteralPath $OutputFile -Value $stdout -Encoding UTF8
    }
  }
  finally {
    $Script:ActiveProcess = $null
  }
}

function Write-RcloneConfig {
  param(
    [Parameter(Mandatory = $true)][string]$AccessKeyId,
    [Parameter(Mandatory = $true)][string]$SecretAccessKey,
    [string]$SessionToken
  )

  $content = @"
[$RemoteName]
type = s3
provider = AWS
env_auth = false
access_key_id = $AccessKeyId
secret_access_key = $SecretAccessKey
region = $Region
location_constraint = $Region
"@
  if (-not [string]::IsNullOrWhiteSpace($SessionToken)) {
    $content = $content + "`nsession_token = $SessionToken"
  }
  Set-Content -LiteralPath $Script:ConfigFile -Value $content -Encoding ASCII
}

function Get-Credentials {
  $accessKeyId = $env:AWS_ACCESS_KEY_ID
  $secretAccessKey = $env:AWS_SECRET_ACCESS_KEY
  if ([string]::IsNullOrWhiteSpace($secretAccessKey)) {
    $secretAccessKey = $env:AWS_SECRET_KEY
  }
  $sessionToken = $env:AWS_SESSION_TOKEN

  Write-Host "AWS credentials"
  Write-Host "---------------"

  if ([string]::IsNullOrWhiteSpace($accessKeyId)) {
    $accessKeyId = Read-Host "AWS Access Key ID"
  }
  else {
    Write-Host "AWS Access Key ID: using AWS_ACCESS_KEY_ID from environment"
  }

  if ([string]::IsNullOrWhiteSpace($secretAccessKey)) {
    $secureKey = Read-Host "AWS Secret Access Key" -AsSecureString
    $secretAccessKey = ConvertTo-PlainText $secureKey
  }
  else {
    Write-Host "AWS Secret Access Key: using AWS_SECRET_ACCESS_KEY from environment"
  }

  if ([string]::IsNullOrWhiteSpace($accessKeyId) -or [string]::IsNullOrWhiteSpace($secretAccessKey)) {
    throw "AWS Access Key ID and AWS Secret Access Key are required. AWS IAM username/password cannot be used by rclone/S3."
  }

  [PSCustomObject]@{
    AccessKeyId = $accessKeyId
    SecretAccessKey = $secretAccessKey
    SessionToken = $sessionToken
  }
}

function Wait-Menu {
  Write-Host ""
  Read-Host "Press Enter to return to the menu" | Out-Null
}

function Select-DatasetVariant {
  Write-Host ""
  $answer = Read-Host "Download the smaller sample with scene/task_category L2 directory structure? [y/N]"
  if ($answer -in @("y", "Y", "yes", "YES")) {
    $Script:Prefix = $Script:SmallerPrefix
    $Script:DefaultDestDir = $Script:SmallerDefaultDestDir
    $Script:DatasetTitle = "Smaller Sample"
    $Script:DatasetSizeMessage = "The smaller sample is smaller than the full dataset, but make sure the destination disk has enough space."
    $Script:RecommendedGiB = 30
  }
  else {
    $Script:Prefix = $Script:FullPrefix
    $Script:DefaultDestDir = $Script:FullDefaultDestDir
    $Script:DatasetTitle = "Data Sample Plain"
    $Script:DatasetSizeMessage = "Dataset size is about 88GB. Make sure the destination disk has enough space."
    $Script:RecommendedGiB = 100
  }
}

function Preview-Dataset {
  $dirListFile = Join-Path $Script:TempDir "sample_dirs.txt"

  Write-Host ""
  Write-Host "Preview: $($Script:DatasetTitle)"
  Write-Host "--------------------------"
  Write-Host "S3 URI: s3://$Bucket/$($Script:Prefix)/"
  Write-Host "Region: $Region"
  Write-Host ""
  Write-Host "Reading dataset size and file count..."
  Invoke-Rclone -Arguments @("size", $Script:RemotePath)
  Write-Host ""
  Write-Host "Root files under the dataset prefix:"
  Invoke-Rclone -Arguments @("lsf", $Script:RemotePath, "--max-depth", "1", "--files-only")
  Write-Host ""
  Write-Host "First sample folders:"
  Invoke-Rclone -Arguments @("lsf", $Script:RemotePath, "--dirs-only") -OutputFile $dirListFile
  $dirs = Get-Content -LiteralPath $dirListFile
  $dirs | Select-Object -First 20 | ForEach-Object { Write-Host $_ }
  if ($dirs.Count -gt 20) {
    Write-Host "... and $($dirs.Count - 20) more sample folders"
  }
  Write-Host ""
  Write-Host "Preview complete."
}

function Get-NearestExistingParent {
  param([Parameter(Mandatory = $true)][string]$Path)

  $current = [System.IO.Path]::GetFullPath($Path)
  while (-not (Test-Path -LiteralPath $current)) {
    $parent = Split-Path -Parent $current
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
      return $current
    }
    $current = $parent
  }
  return $current
}

function Confirm-DiskSpace {
  param([Parameter(Mandatory = $true)][string]$DestDir)

  $parent = Get-NearestExistingParent $DestDir
  try {
    $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
    $root = [System.IO.Path]::GetPathRoot($resolvedParent)
    $driveName = $root.TrimEnd("\").TrimEnd(":")
    $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
    $availableGiB = [math]::Floor($drive.Free / 1GB)
    Write-Host ""
    Write-Host "Disk space check:"
    Write-Host "  Destination parent: $parent"
    Write-Host "  Available: $availableGiB GiB"
    Write-Host "  Recommended: at least $($Script:RecommendedGiB) GiB"
    $recommendedBytes = [int64]($Script:RecommendedGiB) * 1GB
    if ($drive.Free -lt $recommendedBytes) {
      Write-Host ""
      Write-Host "Warning: available space may be too low for the selected dataset."
      $answer = Read-Host "Continue anyway? [y/N]"
      if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Download cancelled."
        return $false
      }
    }
  }
  catch {
    Write-Host "Warning: could not check disk space. Continuing..."
  }
  return $true
}

function Download-Dataset {
  Write-Host ""
  Write-Host "Download: $($Script:DatasetTitle)"
  Write-Host "---------------------------"
  Write-Host $Script:DatasetSizeMessage
  Write-Host ""
  $destDir = Read-Host "Download directory [$DefaultDestDir]"
  if ([string]::IsNullOrWhiteSpace($destDir)) {
    $destDir = $DefaultDestDir
  }
  $destDir = Resolve-UserPath $destDir

  if (-not (Confirm-DiskSpace $destDir)) {
    return
  }

  Write-Host ""
  Write-Host "Source: s3://$Bucket/$($Script:Prefix)/"
  Write-Host "Destination: $destDir"
  Write-Host "Parallel transfers: $Transfers"
  Write-Host "Large-file streams: $MultiThreadStreams"
  Write-Host ""
  $answer = Read-Host "Start download now? [Y/n]"
  if ($answer -in @("n", "N", "no", "NO")) {
    Write-Host "Download cancelled."
    return
  }

  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Invoke-Rclone -Arguments @(
    "copy", $Script:RemotePath, $destDir,
    "--progress",
    "--stats", "10s",
    "--checkers", $Checkers,
    "--transfers", $Transfers,
    "--multi-thread-streams", $MultiThreadStreams,
    "--multi-thread-cutoff", $MultiThreadCutoff
  )

  Write-Host ""
  Write-Host "Download complete."
  Write-Host "Local directory: $destDir"
}

function Show-Menu {
  while ($true) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "$($Script:DatasetTitle) - AWS S3"
    Write-Host "========================================"
    Write-Host "1) Preview dataset"
    Write-Host "2) Download dataset"
    Write-Host "3) Preview, then download"
    Write-Host "q) Quit"
    Write-Host ""
    $choice = Read-Host "Choose an option [1/2/3/q]"

    switch ($choice) {
      "1" {
        Preview-Dataset
        Wait-Menu
      }
      "2" {
        Download-Dataset
        Wait-Menu
      }
      "3" {
        Preview-Dataset
        Download-Dataset
        Wait-Menu
      }
      { $_ -in @("q", "Q") } {
        Write-Host "Bye."
        return
      }
      default {
        Write-Host "Invalid option. Please choose 1, 2, 3, or q."
      }
    }
  }
}

if ($args.Count -gt 0) {
  if ($args[0] -in @("-h", "--help", "-Help", "/?")) {
    Show-Usage
    exit 0
  }
  Write-Host "Error: unknown argument: $($args[0])" -ForegroundColor Red
  Show-Usage
  exit 1
}

Require-Command "rclone"

$cancelHandler = [ConsoleCancelEventHandler]{
  param($sender, $eventArgs)
  $eventArgs.Cancel = $true
  Write-Host ""
  Write-Host "Interrupted. Stopping rclone..." -ForegroundColor Yellow
  Stop-ActiveRclone
  Cleanup
  [Environment]::Exit(130)
}
[Console]::add_CancelKeyPress($cancelHandler)

try {
  $Script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("data-sample-aws-" + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Force -Path $Script:TempDir | Out-Null
  $Script:ConfigFile = Join-Path $Script:TempDir "rclone.conf"
  Select-DatasetVariant
  $Script:RemotePath = "${RemoteName}:${Bucket}/$($Script:Prefix)"

  $creds = Get-Credentials
  Write-RcloneConfig -AccessKeyId $creds.AccessKeyId -SecretAccessKey $creds.SecretAccessKey -SessionToken $creds.SessionToken
  Show-Menu
}
catch {
  Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
finally {
  Cleanup
}
