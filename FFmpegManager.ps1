function Ensure-FFmpeg {
    <#
    .SYNOPSIS
    Ensures FFmpeg is installed and up-to-date
    
    .DESCRIPTION
    Checks if FFmpeg exists, verifies version, and downloads/updates if needed
    
    .OUTPUTS
    Returns the path to ffmpeg.exe
    #>
    
    [CmdletBinding()]
    param()
    
    $ffmpegDir = $PSScriptRoot + "\ffmpeg"
    $ffmpegExe = $ffmpegDir + "\bin\ffmpeg.exe"
    $versionFile = $ffmpegDir + "\.version.txt"
    
    # Check if FFmpeg exists
    $needsDownload = $false
    
    if(!(Test-Path $ffmpegExe)) {
        Write-Host "FFmpeg not found, will download..." -ForegroundColor Yellow
        $needsDownload = $true
    }
    else {
        # Check version age
        if(Test-Path $versionFile) {
            try {
                $versionInfo = Get-Content $versionFile -Raw | ConvertFrom-Json
                $downloadDate = [DateTime]::Parse($versionInfo.DownloadDate)
                $daysSinceDownload = (New-TimeSpan -Start $downloadDate -End (Get-Date)).Days
                
                Write-Host "FFmpeg installed on: $($downloadDate.ToString('yyyy-MM-dd')) ($daysSinceDownload days ago)"
                
                # Prompt for update if older than 30 days
                if($daysSinceDownload -gt 30) {
                    Write-Host "FFmpeg is more than 30 days old. Checking for updates..." -ForegroundColor Yellow
                    
                    # Get latest release info from GitHub
                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest"
                        $latestDate = [DateTime]::Parse($latestRelease.published_at)
                        
                        if($latestDate -gt $downloadDate) {
                            Write-Host "Newer version available (published: $($latestDate.ToString('yyyy-MM-dd')))" -ForegroundColor Green
                            $needsDownload = $true
                        }
                        else {
                            Write-Host "FFmpeg is up-to-date" -ForegroundColor Green
                        }
                    }
                    catch {
                        Write-Host "Could not check for updates: $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-Host "Continuing with existing FFmpeg installation" -ForegroundColor Gray
                    }
                }
            }
            catch {
                Write-Host "Could not read version file, will re-download FFmpeg" -ForegroundColor Yellow
                $needsDownload = $true
            }
        }
        else {
            # No version file, assume old installation
            Write-Host "No version information found. FFmpeg will be updated." -ForegroundColor Yellow
            $needsDownload = $true
        }
    }
    
    # Download/Update FFmpeg if needed
    if($needsDownload) {
        try {
            Write-Host "Downloading FFmpeg..." -ForegroundColor Cyan
            
            # Enable TLS 1.2 for HTTPS downloads
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            $ffmpegDL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip"
            $zipPath = $PSScriptRoot + "\ffmpeg.zip"
            $tempExtract = $PSScriptRoot + "\ffmpeg_temp"
            
            # Clear existing ffmpeg directory if it exists
            if(Test-Path $ffmpegDir) {
                Write-Host "Removing old FFmpeg installation..." -ForegroundColor Gray
                Remove-Item -Path $ffmpegDir -Recurse -Force
            }
            
            # Create fresh ffmpeg directory
            New-Item -ItemType Directory -Path $ffmpegDir -Force | Out-Null
            
            # Download
            Write-Host "Downloading from GitHub..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $ffmpegDL -OutFile $zipPath
            
            # Extract
            Write-Host "Extracting..." -ForegroundColor Gray
            Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force
            
            # Move contents from the extracted subfolder to /ffmpeg, preserving structure
            $extractedFolder = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
            if($extractedFolder) {
                Get-ChildItem -Path $extractedFolder.FullName | ForEach-Object {
                    Move-Item -Path $_.FullName -Destination $ffmpegDir -Force
                }
            }
            
            # Save version info
            $versionInfo = @{
                DownloadDate = (Get-Date).ToString("o")
                Source = $ffmpegDL
            }
            $versionInfo | ConvertTo-Json | Out-File -FilePath $versionFile -Encoding UTF8
            
            # Cleanup
            Remove-Item -Path $zipPath -Force
            Remove-Item -Path $tempExtract -Recurse -Force
            
            Write-Host "FFmpeg installed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to download FFmpeg: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }
    
    # Verify installation and return paths
    if(!(Test-Path $ffmpegExe)) {
        throw "FFmpeg installation failed - ffmpeg.exe not found"
    }
    
    return @{
        FFmpeg = $ffmpegExe
        FFprobe = $ffmpegDir + "\bin\ffprobe.exe"
        Directory = $ffmpegDir
    }
}
