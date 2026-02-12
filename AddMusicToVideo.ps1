function Add-MusicToVideo {
    [CmdletBinding()]
    param (
        [string]$VideoPath,
        [string]$MusicPath,
        [string]$OutputPath,
        [double]$MusicVolume,
        [double]$OriginalVolume,
        [switch]$RepeatSingleSong  # If true, loop the music to fill video length
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
        . "$PSScriptRoot\PrereqManager.ps1"
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
            # Normalize both audio streams to same loudness level (EBU R128 standard), then mix
            # This ensures predictable mixing regardless of how loud the source files are
            # -filter_complex "[0:a]loudnorm,volume=1.0[orig];[1:a]loudnorm,volume=0.2[music];[orig][music]amix"
            
            # Determine if we need to loop the music
            $streamLoopArg = ""
            if($RepeatSingleSong -and $musicLength -lt $videoLength) {
                write-host "Music is shorter than video - will loop music to fill video" -ForegroundColor Yellow
                $streamLoopArg = "-stream_loop -1 "
            }
            
            $arguments = "-i " + [char]34 + $VideoPath + [char]34 + " "
            $arguments += $streamLoopArg + "-i " + [char]34 + $MusicPath + [char]34 + " "
            $arguments += "-filter_complex " + [char]34
            $arguments += "[0:a]loudnorm=I=-16:TP=-1.5:LRA=11,volume=$OriginalVolume[orig];"
            $arguments += "[1:a]loudnorm=I=-16:TP=-1.5:LRA=11,volume=$MusicVolume[music];"
            $arguments += "[orig][music]amix=inputs=2:duration=longest:dropout_transition=2:normalize=0[aout]"
            $arguments += [char]34 + " "
            $arguments += "-map 0:v -map " + [char]34 + "[aout]" + [char]34 + " "
            $arguments += "-shortest -c:v copy -c:a aac -b:a 192k "
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
