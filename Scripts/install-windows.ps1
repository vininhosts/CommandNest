$ErrorActionPreference = "Stop"

$Repo = if ($env:COMMANDNEST_REPO) { $env:COMMANDNEST_REPO } else { "vininhosts/CommandNest" }
$Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
if ($Architecture -eq "arm64") {
    $ReleaseArch = "arm64"
} else {
    $ReleaseArch = "x64"
}

$Asset = "CommandNest-win32-$ReleaseArch.zip"
$ChecksumAsset = "CommandNest-win32-$ReleaseArch.sha256"
$BaseUrl = "https://github.com/$Repo/releases/latest/download"
$InstallDir = Join-Path $env:LOCALAPPDATA "CommandNest"
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("CommandNest-" + [System.Guid]::NewGuid().ToString())
$ZipPath = Join-Path $TempDir $Asset
$ChecksumPath = Join-Path $TempDir $ChecksumAsset

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

try {
    Write-Host "Downloading CommandNest for Windows $ReleaseArch..."
    Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $ZipPath

    try {
        Invoke-WebRequest -Uri "$BaseUrl/$ChecksumAsset" -OutFile $ChecksumPath
        Write-Host "Verifying checksum..."
        $Expected = (Get-Content $ChecksumPath | Select-Object -First 1).Split(" ")[0].Trim().ToLowerInvariant()
        $Actual = (Get-FileHash -Algorithm SHA256 $ZipPath).Hash.ToLowerInvariant()
        if ($Expected -ne $Actual) {
            throw "Checksum mismatch. Expected $Expected but got $Actual."
        }
    } catch {
        Write-Host "Checksum asset unavailable or verification failed: $($_.Exception.Message)"
        throw
    }

    Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force
    $ExtractedDir = Join-Path $TempDir "CommandNest-win32-$ReleaseArch"
    $Executable = Join-Path $ExtractedDir "CommandNest.exe"
    if (!(Test-Path $Executable)) {
        throw "Downloaded archive did not contain CommandNest.exe."
    }

    Write-Host "Installing to $InstallDir..."
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
    }
    Move-Item $ExtractedDir $InstallDir

    $ShortcutDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $ShortcutPath = Join-Path $ShortcutDir "CommandNest.lnk"
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = Join-Path $InstallDir "CommandNest.exe"
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.Save()

    Start-Process (Join-Path $InstallDir "CommandNest.exe")
    Write-Host "CommandNest installed and launched."
} finally {
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
}
