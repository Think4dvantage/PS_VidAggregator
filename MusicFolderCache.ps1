function Get-MusicFolderCache {
    [CmdletBinding()]
    param (
        [string]$FolderPath,
        [string]$FFprobe
    )
    
    # Create cache directory
    $cacheDir = Join-Path $PSScriptRoot "cache"
    if(!(Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir | Out-Null
    }
    
    # Generate cache filename based on folder path
    $folderHash = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($FolderPath))).Replace("-","")
    $cacheFile = Join-Path $cacheDir "music_cache_$folderHash.json"
    
    # Get current files in folder
    write-host "Scanning folder for music files..." -ForegroundColor Yellow
    $currentFiles = Get-ChildItem -Path $FolderPath -Recurse -Include *.mp3,*.wav,*.m4a,*.aac -ErrorAction SilentlyContinue | Select-Object FullName, LastWriteTime, Length
    $fileCount = $currentFiles.Count
    write-host "Found $fileCount music files" -ForegroundColor Green
    
    if($fileCount -eq 0) {
        return @()
    }
    
    # Check if cache exists and is valid
    $useCache = $false
    if(Test-Path $cacheFile) {
        try {
            $cache = Get-Content -Path $cacheFile -Raw | ConvertFrom-Json
            
            # Validate cache: same file count and folder path
            if($cache.FolderPath -eq $FolderPath -and $cache.Files.Count -eq $fileCount) {
                # Quick validation: check if file list matches
                $cachedPaths = $cache.Files | ForEach-Object { $_.Path }
                $currentPaths = $currentFiles | ForEach-Object { $_.FullName }
                
                $pathsMatch = ($cachedPaths | Sort-Object) -join "|" -eq ($currentPaths | Sort-Object) -join "|"
                
                if($pathsMatch) {
                    write-host "Cache found and valid! Using cached durations (instant)" -ForegroundColor Green
                    $useCache = $true
                }
            }
            
            if(!$useCache) {
                write-host "Cache outdated (folder contents changed), rescanning..." -ForegroundColor Yellow
            }
        }
        catch {
            write-host "Cache file corrupted, rescanning..." -ForegroundColor Yellow
        }
    } else {
        write-host "No cache found, analyzing files (this will be cached for future use)..." -ForegroundColor Yellow
    }
    
    if($useCache) {
        # Return cached data
        $result = @()
        foreach($file in $cache.Files) {
            $result += [PSCustomObject]@{
                Path = $file.Path
                Duration = $file.Duration
                Name = $file.Name
            }
        }
        return $result
    }
    
    # Cache not valid, analyze files
    write-host "Analyzing file durations..." -ForegroundColor Yellow
    $musicFilesWithDuration = @()
    $fileNum = 0
    
    foreach($file in $currentFiles) {
        $fileNum++
        if($fileNum % 10 -eq 0 -or $fileNum -eq 1) {
            write-host "  Progress: $fileNum/$fileCount files analyzed..." -ForegroundColor Gray
        }
        
        try {
            start-process -FilePath $FFprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + [char]34 + $file.FullName + [char]34) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\musiclength.txt -PassThru -Wait | Out-Null
            $musicLength = [int]((get-content C:\Windows\Temp\musiclength.txt).Split(".")[0])
            
            $musicFilesWithDuration += [PSCustomObject]@{
                Path = $file.FullName
                Duration = $musicLength
                Name = Split-Path $file.FullName -Leaf
            }
        }
        catch {
            write-host "  Failed to analyze: $($file.FullName)" -ForegroundColor Yellow
        }
    }
    
    # Save to cache
    try {
        $cacheData = @{
            FolderPath = $FolderPath
            CachedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Files = $musicFilesWithDuration | ForEach-Object {
                @{
                    Path = $_.Path
                    Duration = $_.Duration
                    Name = $_.Name
                }
            }
        }
        
        $cacheData | ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFile -Encoding UTF8
        write-host "Cache saved for future use!" -ForegroundColor Green
    }
    catch {
        write-host "Warning: Could not save cache: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    return $musicFilesWithDuration
}

function Clear-MusicFolderCache {
    [CmdletBinding()]
    param (
        [string]$FolderPath = $null  # If null, clears all cache
    )
    
    $cacheDir = Join-Path $PSScriptRoot "cache"
    
    if([string]::IsNullOrWhiteSpace($FolderPath)) {
        # Clear all cache
        if(Test-Path $cacheDir) {
            Remove-Item -Path "$cacheDir\music_cache_*.json" -Force
            write-host "All music folder caches cleared" -ForegroundColor Green
        }
    } else {
        # Clear specific folder cache
        $folderHash = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($FolderPath))).Replace("-","")
        $cacheFile = Join-Path $cacheDir "music_cache_$folderHash.json"
        
        if(Test-Path $cacheFile) {
            Remove-Item -Path $cacheFile -Force
            write-host "Cache cleared for: $FolderPath" -ForegroundColor Green
        }
    }
}
