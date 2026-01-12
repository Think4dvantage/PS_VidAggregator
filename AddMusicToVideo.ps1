function Add-MusicToVideo {
    [CmdletBinding()]
    param (
        [string]$VideoPath,
        [string]$MusicPath,
        [string]$OutputPath,
        [double]$MusicVolume,
        [double]$OriginalVolume
    )
    
    begin {
        # Validate input parameters
        if(![System.IO.File]::Exists($VideoPath)) {
            write-host "Video file not found: $VideoPath" -ForegroundColor Red
            return $false
        }
        
        if(![System.IO.File]::Exists($MusicPath)) {
            write-host "Music file not found: $MusicPath" -ForegroundColor Red
            return $false
        }
        
        # Ensure FFmpeg is installed
        . "$PSScriptRoot\FFmpegManager.ps1"
        try {
            $ffmpegPaths = Ensure-FFmpeg
            $ffmpeg = $ffmpegPaths.FFmpeg
            $ffprobe = $ffmpegPaths.FFprobe
        }
        catch {
            write-host "Failed to initialize FFmpeg: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
        
        # Get video duration
        try {
            start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + [char]34 + $VideoPath + [char]34) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\videolength.txt -PassThru -Wait | Out-Null
            $videoLength = (get-content C:\Windows\Temp\videolength.txt).Split(".")[0]
            write-host "Video Length: $videoLength seconds" -ForegroundColor Cyan
        }
        catch {
            write-host "Failed to detect video length: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
        
        # Get music duration
        try {
            start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + [char]34 + $MusicPath + [char]34) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\musiclength.txt -PassThru -Wait | Out-Null
            $musicLength = (get-content C:\Windows\Temp\musiclength.txt).Split(".")[0]
            write-host "Music Length: $musicLength seconds" -ForegroundColor Cyan
        }
        catch {
            write-host "Failed to detect music length: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    process {
        try {
            write-host "`nAdding background music to video..." -ForegroundColor Green
            write-host "  Video: $VideoPath" -ForegroundColor Gray
            write-host "  Music: $MusicPath" -ForegroundColor Gray
            write-host "  Music Volume: $($MusicVolume * 100)%" -ForegroundColor Gray
            write-host "  Original Volume: $($OriginalVolume * 100)%" -ForegroundColor Gray
            write-host "  Output: $OutputPath" -ForegroundColor Gray
            
            # Build FFmpeg command
            # -i video -stream_loop -1 -i music
            # -filter_complex "[0:a]volume=0.6[orig];[1:a]volume=0.4[music];[orig][music]amix=inputs=2:duration=first[aout]"
            # -map 0:v -map [aout] -c:v copy -c:a aac -b:a 192k output.mp4
            
            $arguments = "-i " + [char]34 + $VideoPath + [char]34 + " "
            $arguments += "-stream_loop -1 -i " + [char]34 + $MusicPath + [char]34 + " "
            $arguments += "-filter_complex " + [char]34
            $arguments += "[0:a]volume=$OriginalVolume[orig];"
            $arguments += "[1:a]volume=$MusicVolume[music];"
            $arguments += "[orig][music]amix=inputs=2:duration=first:dropout_transition=2[aout]"
            $arguments += [char]34 + " "
            $arguments += "-map 0:v -map " + [char]34 + "[aout]" + [char]34 + " "
            $arguments += "-c:v copy -c:a aac -b:a 192k "
            $arguments += [char]34 + $OutputPath + [char]34 + " -y"
            
            write-host "`nFFmpeg command:" -ForegroundColor Cyan
            write-host $arguments -ForegroundColor Gray
            
            write-host "`nProcessing video... (this may take a while)" -ForegroundColor Yellow
            $process = start-process -FilePath $ffmpeg -ArgumentList $arguments -PassThru -Wait -NoNewWindow
            
            if($process.ExitCode -ne 0) {
                write-host "FFmpeg process failed with exit code: $($process.ExitCode)" -ForegroundColor Red
                return $false
            }
            
            # Verify output file exists
            if(!(Test-Path $OutputPath)) {
                write-host "Output file was not created" -ForegroundColor Red
                return $false
            }
            
            # Get output file size
            $outputSize = (Get-Item $OutputPath).Length
            if($outputSize -lt 1000) {
                write-host "Output file is too small ($outputSize bytes), something went wrong" -ForegroundColor Red
                return $false
            }
            
            write-host "`nSuccess! Video with background music created:" -ForegroundColor Green
            write-host "  $OutputPath" -ForegroundColor Green
            write-host "  Size: $([math]::Round($outputSize / 1MB, 2)) MB" -ForegroundColor Gray
            
            return $true
        }
        catch {
            write-host "Error during processing: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    end {
        write-host "Done." -ForegroundColor Cyan
    }
}
