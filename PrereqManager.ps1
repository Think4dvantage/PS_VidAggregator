# PrereqManager.ps1
# Ensures all prerequisites are installed: FFmpeg, Python, and required Python packages

function Ensure-Prerequisites {
    <#
    .SYNOPSIS
    Ensures all prerequisites are installed and configured
    
    .DESCRIPTION
    Checks and installs:
    - FFmpeg (for video processing)
    - Python (for Whisper AI)
    - Python packages (whisper, torch, soundfile, scipy, packaging)
    
    .OUTPUTS
    Returns hashtable with paths and status
    #>
    
    [CmdletBinding()]
    param(
        [switch]$Silent = $false
    )
    
    $results = @{
        FFmpeg = $null
        Python = $null
        PythonPackages = @{
            whisper = $false
            torch = $false
            soundfile = $false
            scipy = $false
            packaging = $false
        }
        Success = $true
    }
    
    # ===== 1. Ensure FFmpeg =====
    if(-not $Silent) {
        Write-Host "`n=== Checking FFmpeg ===" -ForegroundColor Cyan
    }
    
    try {
        $ffmpegResult = Ensure-FFmpeg -Silent:$Silent
        $results.FFmpeg = $ffmpegResult
        if(-not $Silent) {
            Write-Host "FFmpeg: OK" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "FFmpeg: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results.Success = $false
        return $results
    }
    
    # ===== 2. Ensure Python =====
    if(-not $Silent) {
        Write-Host "`n=== Checking Python ===" -ForegroundColor Cyan
    }
    
    try {
        $pythonPath = Ensure-Python -Silent:$Silent
        $results.Python = $pythonPath
        if(-not $Silent) {
            Write-Host "Python: OK ($pythonPath)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Python: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results.Success = $false
        return $results
    }
    
    # ===== 3. Ensure Python Packages =====
    if(-not $Silent) {
        Write-Host "`n=== Checking Python Packages ===" -ForegroundColor Cyan
    }
    
    try {
        $packageResults = Ensure-PythonPackages -Silent:$Silent
        $results.PythonPackages = $packageResults
        
        $allInstalled = $true
        foreach($pkg in $packageResults.Keys) {
            if(-not $packageResults[$pkg]) {
                $allInstalled = $false
                break
            }
        }
        
        if(-not $Silent) {
            if($allInstalled) {
                Write-Host "All Python packages: OK" -ForegroundColor Green
            } else {
                Write-Host "Some Python packages need installation" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Python packages check: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results.Success = $false
    }
    
    if(-not $Silent) {
        Write-Host "`n=== Prerequisites Check Complete ===" -ForegroundColor Cyan
    }
    
    return $results
}

function Ensure-FFmpeg {
    <#
    .SYNOPSIS
    Ensures FFmpeg is installed and up-to-date
    
    .DESCRIPTION
    Checks if FFmpeg exists, verifies version, and downloads/updates if needed
    
    .OUTPUTS
    Returns hashtable with FFmpeg paths
    #>
    
    [CmdletBinding()]
    param(
        [switch]$Silent = $false
    )
    
    $ffmpegDir = $PSScriptRoot + "\ffmpeg"
    $ffmpegExe = $ffmpegDir + "\bin\ffmpeg.exe"
    $versionFile = $ffmpegDir + "\.version.txt"
    
    # Check if FFmpeg exists
    $needsDownload = $false
    
    if(!(Test-Path $ffmpegExe)) {
        if(-not $Silent) {
            Write-Host "FFmpeg not found, will download..." -ForegroundColor Yellow
        }
        $needsDownload = $true
    }
    else {
        # Check version age
        if(Test-Path $versionFile) {
            try {
                $versionInfo = Get-Content $versionFile -Raw | ConvertFrom-Json
                $downloadDate = [DateTime]::Parse($versionInfo.DownloadDate)
                $daysSinceDownload = (New-TimeSpan -Start $downloadDate -End (Get-Date)).Days
                
                if(-not $Silent) {
                    Write-Host "FFmpeg installed on: $($downloadDate.ToString('yyyy-MM-dd')) ($daysSinceDownload days ago)"
                }
                
                # Check for updates if older than 30 days
                if($daysSinceDownload -gt 30) {
                    if(-not $Silent) {
                        Write-Host "FFmpeg is more than 30 days old. Checking for updates..." -ForegroundColor Yellow
                    }
                    
                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest"
                        $latestDate = [DateTime]::Parse($latestRelease.published_at)
                        
                        if($latestDate -gt $downloadDate) {
                            if(-not $Silent) {
                                Write-Host "Newer version available (published: $($latestDate.ToString('yyyy-MM-dd')))" -ForegroundColor Green
                            }
                            $needsDownload = $true
                        }
                        else {
                            if(-not $Silent) {
                                Write-Host "FFmpeg is up-to-date" -ForegroundColor Green
                            }
                        }
                    }
                    catch {
                        if(-not $Silent) {
                            Write-Host "Could not check for updates: $($_.Exception.Message)" -ForegroundColor Yellow
                            Write-Host "Continuing with existing FFmpeg installation" -ForegroundColor Gray
                        }
                    }
                }
            }
            catch {
                if(-not $Silent) {
                    Write-Host "Could not read version file, will re-download FFmpeg" -ForegroundColor Yellow
                }
                $needsDownload = $true
            }
        }
        else {
            if(-not $Silent) {
                Write-Host "No version information found. FFmpeg will be updated." -ForegroundColor Yellow
            }
            $needsDownload = $true
        }
    }
    
    # Download/Update FFmpeg if needed
    if($needsDownload) {
        try {
            if(-not $Silent) {
                Write-Host "Downloading FFmpeg..." -ForegroundColor Cyan
            }
            
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            $ffmpegDL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip"
            $zipPath = $PSScriptRoot + "\ffmpeg.zip"
            $tempExtract = $PSScriptRoot + "\ffmpeg_temp"
            
            if(Test-Path $ffmpegDir) {
                if(-not $Silent) {
                    Write-Host "Removing old FFmpeg installation..." -ForegroundColor Gray
                }
                Remove-Item -Path $ffmpegDir -Recurse -Force
            }
            
            New-Item -ItemType Directory -Path $ffmpegDir -Force | Out-Null
            
            if(-not $Silent) {
                Write-Host "Downloading from GitHub..." -ForegroundColor Gray
            }
            Invoke-WebRequest -Uri $ffmpegDL -OutFile $zipPath
            
            if(-not $Silent) {
                Write-Host "Extracting..." -ForegroundColor Gray
            }
            Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force
            
            $extractedFolder = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
            if($extractedFolder) {
                Get-ChildItem -Path $extractedFolder.FullName | ForEach-Object {
                    Move-Item -Path $_.FullName -Destination $ffmpegDir -Force
                }
            }
            
            $versionInfo = @{
                DownloadDate = (Get-Date).ToString("o")
                Source = $ffmpegDL
            }
            $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding UTF8
            
            Remove-Item -Path $zipPath -Force
            Remove-Item -Path $tempExtract -Recurse -Force
            
            if(-not $Silent) {
                Write-Host "FFmpeg installed successfully!" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Failed to download FFmpeg: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }
    
    if(!(Test-Path $ffmpegExe)) {
        throw "FFmpeg installation failed - ffmpeg.exe not found"
    }
    
    return @{
        FFmpeg = $ffmpegExe
        FFprobe = $ffmpegDir + "\bin\ffprobe.exe"
        Directory = $ffmpegDir
    }
}

function Ensure-Python {
    <#
    .SYNOPSIS
    Ensures Python is installed
    
    .DESCRIPTION
    Checks if Python exists, and installs via winget if needed
    
    .OUTPUTS
    Returns path to python.exe
    #>
    
    [CmdletBinding()]
    param(
        [switch]$Silent = $false
    )
    
    # Check if Python is in PATH
    try {
        $pythonCheck = & python --version 2>&1
        if($pythonCheck -match 'Python (\d+\.\d+\.\d+)') {
            $pythonVersion = $matches[1]
            if(-not $Silent) {
                Write-Host "Python $pythonVersion detected" -ForegroundColor Green
            }
            
            # Get python path
            $pythonPath = (Get-Command python -ErrorAction Stop).Source
            return $pythonPath
        }
    }
    catch {
        # Python not found
    }
    
    # Python not found, offer to install
    if(-not $Silent) {
        Write-Host "Python not found" -ForegroundColor Yellow
        Write-Host "Python is required for speech extraction (Whisper AI)" -ForegroundColor Gray
        
        # Check if winget is available
        try {
            $wingetCheck = & winget --version 2>&1
            if($wingetCheck) {
                Write-Host "`nAttempting to install Python via winget..." -ForegroundColor Cyan
                
                # Install Python via winget
                Write-Host "Running: winget install -e --id Python.Python.3.13" -ForegroundColor Gray
                $installProcess = Start-Process -FilePath "winget" -ArgumentList "install -e --id Python.Python.3.13 --silent" -NoNewWindow -Wait -PassThru
                
                if($installProcess.ExitCode -eq 0) {
                    Write-Host "Python installed successfully!" -ForegroundColor Green
                    Write-Host "Please restart PowerShell and run the application again." -ForegroundColor Yellow
                    Write-Host "(Python needs to be added to PATH, which requires a shell restart)" -ForegroundColor Gray
                    
                    # Try to find Python in common locations
                    $commonPaths = @(
                        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
                        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
                        "C:\Program Files\Python313\python.exe",
                        "C:\Program Files\Python312\python.exe"
                    )
                    
                    foreach($path in $commonPaths) {
                        if(Test-Path $path) {
                            Write-Host "`nPython found at: $path" -ForegroundColor Green
                            return $path
                        }
                    }
                    
                    throw "Python installed but not found in PATH. Please restart PowerShell."
                }
                else {
                    Write-Host "Python installation failed (Exit code: $($installProcess.ExitCode))" -ForegroundColor Red
                    throw "Failed to install Python via winget"
                }
            }
        }
        catch {
            Write-Host "Cannot install Python automatically" -ForegroundColor Red
            Write-Host "Please install Python manually:" -ForegroundColor Yellow
            Write-Host "  Option 1: Run 'winget install Python.Python.3.13' in PowerShell" -ForegroundColor Cyan
            Write-Host "  Option 2: Download from https://www.python.org/downloads/" -ForegroundColor Cyan
            Write-Host "  (Make sure to check 'Add Python to PATH' during installation)" -ForegroundColor Gray
            throw "Python not installed"
        }
    }
    
    throw "Python not found"
}

function Ensure-PythonPackages {
    <#
    .SYNOPSIS
    Ensures required Python packages are installed
    
    .DESCRIPTION
    Checks and installs: openai-whisper, torch, soundfile, scipy, packaging
    
    .OUTPUTS
    Returns hashtable with package installation status
    #>
    
    [CmdletBinding()]
    param(
        [switch]$Silent = $false
    )
    
    $packages = @{
        'whisper' = @{
            Name = 'openai-whisper'
            ImportName = 'whisper'
        }
        'torch' = @{
            Name = 'torch'
            ImportName = 'torch'
            InstallCmd = 'pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118'
        }
        'soundfile' = @{
            Name = 'soundfile'
            ImportName = 'soundfile'
        }
        'scipy' = @{
            Name = 'scipy'
            ImportName = 'scipy'
        }
        'packaging' = @{
            Name = 'packaging'
            ImportName = 'packaging'
        }
    }
    
    $results = @{}
    $needsInstall = @()
    
    # Check each package
    foreach($key in $packages.Keys) {
        $pkg = $packages[$key]
        $importName = $pkg.ImportName
        
        try {
            $checkResult = & python -c "import $importName; print('OK')" 2>&1
            if($checkResult -match 'OK') {
                $results[$key] = $true
                if(-not $Silent) {
                    Write-Host "  $key : Installed" -ForegroundColor Green
                }
            }
            else {
                $results[$key] = $false
                $needsInstall += $key
                if(-not $Silent) {
                    Write-Host "  $key : Not installed" -ForegroundColor Yellow
                }
            }
        }
        catch {
            $results[$key] = $false
            $needsInstall += $key
            if(-not $Silent) {
                Write-Host "  $key : Not installed" -ForegroundColor Yellow
            }
        }
    }
    
    # Install missing packages
    if($needsInstall.Count -gt 0 -and -not $Silent) {
        Write-Host "`nInstalling missing Python packages..." -ForegroundColor Cyan
        
        foreach($key in $needsInstall) {
            $pkg = $packages[$key]
            
            if($pkg.InstallCmd) {
                # Custom install command (e.g., PyTorch with CUDA)
                Write-Host "Installing $key (with GPU support)..." -ForegroundColor Gray
                $installCmd = $pkg.InstallCmd
                Invoke-Expression $installCmd
            }
            else {
                # Standard pip install
                Write-Host "Installing $($pkg.Name)..." -ForegroundColor Gray
                & pip install $pkg.Name
            }
            
            if($LASTEXITCODE -eq 0) {
                Write-Host "  $key installed successfully" -ForegroundColor Green
                $results[$key] = $true
            }
            else {
                Write-Host "  $key installation failed" -ForegroundColor Red
                $results[$key] = $false
            }
        }
    }
    
    return $results
}
