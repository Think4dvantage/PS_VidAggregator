function aggregate-Video {
    [CmdletBinding()]
    param (
        [string]$SourceVideoPath,
        [array]$Highlights,
        [int]$OutputLength,
        [int]$PartLength,
        [string]$OutputPath,
        [hashtable]$BackgroundMusic = $null
    )
    
    begin {
        # Validate input parameters
        if(![System.IO.File]::Exists($SourceVideoPath)) {
            write-host "Source video file not found: $SourceVideoPath" -ForegroundColor Red
            return $false
        }
        
        if($Highlights.Count -eq 0) {
            write-host "No highlights provided" -ForegroundColor Red
            return $false
        }
        
        if($OutputLength -le 0) {
            write-host "Invalid output length: $OutputLength" -ForegroundColor Red
            return $false
        }
        
        # Ensure FFmpeg is installed and up-to-date
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

        try {
            start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + $SourceVideoPath) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\length.txt -PassThru -Wait | Out-Null
            $SourceVideoLength = (get-content C:\Windows\Temp\length.txt).Split(".")[0]
            write-host ("Source Video Length: " + $SourceVideoLength)
        }
        catch {
            write-host "Failed to detect video length: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }

        function calc-partLength($hl)
        {
            $tmplngth = 0
            foreach($prt in $hl)
            {
                if($prt.type -eq "picture") {
                    $tmplngth += $prt.duration
                }
                else {
                    $tmplngth += $prt.end - $prt.start
                }
            }
            return $tmplngth
        }

        # Separate video and picture highlights
        $videoHighlights = $Highlights | where-object {$_.type -eq "video"}
        $pictureHighlights = $Highlights | where-object {$_.type -eq "picture"}
        
        write-host "Video highlights: $($videoHighlights.Count), Picture highlights: $($pictureHighlights.Count)"
        
        # Validate video highlights only
        $provLength = 0 
        foreach ($part in $videoHighlights) {
            if ($part.start -gt $part.end) {
                write-host ("Invalid video highlight - start is greater than end: Removing!")
                $videoHighlights = $videoHighlights | where-object {$_.start -ne $part.start -and $_.end -ne $part.end}
            }
            elseif($part.start -ge $SourceVideoLength -or $part.end -gt $SourceVideoLength)
            {
                $videoHighlights = $videoHighlights | where-object {$_.start -ne $part.start -and $_.end -ne $part.end}
                write-host "Removing part that is bigger than the actual Length of Video"
            }
        }
        
        # Validate picture highlights
        foreach($pic in $pictureHighlights) {
            if(![System.IO.File]::Exists($pic.imagePath)) {
                write-host "Picture file not found: $($pic.imagePath) - Removing highlight" -ForegroundColor Red
                $pictureHighlights = $pictureHighlights | where-object {$_.imagePath -ne $pic.imagePath}
            }
        }
        
        # Recombine all highlights
        $Highlights = @($videoHighlights) + @($pictureHighlights)
        
        $provLength = calc-partLength $Highlights
        $LeftoverOutputLength = $OutputLength - $provLength
        write-host ("Video Length left after Highlights: " + $LeftoverOutputLength)
        $addParts = [int]($LeftoverOutputLength / $PartLength)
        write-host ("Parts to add after Highlight:" + $addParts)
        
        # Find the last VIDEO highlight end time to avoid adding parts after it
        if($videoHighlights.Count -gt 0) {
            $videoHighlights = $videoHighlights | sort-object start
            $lastHighlightEnd = ($videoHighlights | Measure-Object -Property end -Maximum).Maximum
        }
        else {
            $lastHighlightEnd = $SourceVideoLength
        }
        write-host ("Last video highlight ends at: " + $lastHighlightEnd)
        
        $Increment = [int]($lastHighlightEnd / $addparts)
        write-host ("Increment is: " + $Increment)
        $start = 0
        $end = 0
        write-host $Highlights
        do {
            $start = $start + $Increment
            $end = $start + $PartLength
            if($end -ge $lastHighlightEnd)
            {
                $Highlights = $Highlights | sort-object start
                $provLength = calc-partLength $Highlights
                write-host ("Highest Part length has been reached still " + ($OutputLength - $provLength).toString() + " Seconds missing. Adding to each part")
                for ($i = 0; $i -lt ($Highlights.Count -1); $i++) {
                    write-host $i
                    $Highlights[$i].end = $Highlights[$i].end + 1
                    if((calc-partLength $Highlights) -ge $OutputLength)
                    {
                        break
                    }
                }
                break
            }
            $inputPart = ([PSCustomObject]@{type="video"; start=$start; end=$end})
            $videoHighlights = ($videoHighlights | sort-object start)
            
            # Check if the new part overlaps with any existing VIDEO highlight
            $hasOverlap = $false
            foreach ($part in $videoHighlights) {
                # Check all overlap scenarios:
                # 1. New part completely inside existing part
                # 2. New part starts inside existing part
                # 3. New part ends inside existing part  
                # 4. New part completely contains existing part
                if (($inputPart.start -ge $part.start -and $inputPart.start -le $part.end) -or
                    ($inputPart.end -ge $part.start -and $inputPart.end -le $part.end) -or
                    ($inputPart.start -le $part.start -and $inputPart.end -ge $part.end)) {
                    write-host ("Input part ($($inputPart.start)-$($inputPart.end)) overlaps with existing ($($part.start)-$($part.end)) - skipping")
                    $hasOverlap = $true
                    break
                }
            }
            
            # Only add the part if there's no overlap
            if (-not $hasOverlap) {
                $videoHighlights += $inputPart
                write-host ("Added part: $($inputPart.start)-$($inputPart.end)")
            }
            
            # Recombine video and picture highlights for length calculation
            $Highlights = @($videoHighlights) + @($pictureHighlights)
            $provLength = calc-partLength $Highlights
            
            # If we're close to the target length, extend existing VIDEO parts instead of adding more
            if (($OutputLength - $provLength) -le $partLength -and ($OutputLength - $provLength) -gt 0) {
                $i = 0
                while ($provLength -lt $OutputLength -and $i -lt $videoHighlights.Count) {
                    $videoHighlights[$i].End = $videoHighlights[$i].end + 1
                    $Highlights = @($videoHighlights) + @($pictureHighlights)
                    $provLength = calc-partLength $Highlights
                    $i++
                }
            }
        } while (
            $provLength -le $OutputLength
        )
        
        # Final recombine and sort
        $Highlights = @($videoHighlights) + @($pictureHighlights)
        $Highlights = ($Highlights | sort-object start)
        
        write-host "`n=== Final Highlights Summary ==="
        foreach($h in $Highlights) {
            if($h.type -eq "picture") {
                write-host "Picture: $($h.imagePath) for $($h.duration)s - $($h.comment)"
            }
            else {
                write-host "Video: $($h.start)-$($h.end)s - $($h.comment)"
            }
        }
        write-host "================================`n"
        
    }
    
    process {
                # Detect source video resolution for image scaling
                try {
                    start-process -FilePath $ffprobe -ArgumentList ("-v quiet -select_streams v:0 -show_entries stream=width,height -of csv=p=0 " + $SourceVideoPath) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\resolution.txt -PassThru -Wait | Out-Null
                    $resolutionLine = (get-content C:\Windows\Temp\resolution.txt)
                    $videoWidth = $resolutionLine.Split(",")[0]
                    $videoHeight = $resolutionLine.Split(",")[1]
                    write-host "Source video resolution: ${videoWidth}x${videoHeight}"
                }
                catch {
                    write-host "Could not detect video resolution, defaulting to 3840x2160" -ForegroundColor Yellow
                    $videoWidth = 3840
                    $videoHeight = 2160
                }
                
                # Build input arguments and assign input indices
                $arguments = "-i " + $SourceVideoPath + " "
                $inputIndex = 1  # Start at 1 (0 is source video)
                
                foreach($highlight in $Highlights) {
                    if($highlight.type -eq "picture") {
                        # Add image input with loop
                        $arguments += "-loop 1 -framerate 29.97 -t $($highlight.duration) -i " + [char]34 + $highlight.imagePath + [char]34 + " "
                        $highlight | Add-Member -NotePropertyName "inputIndex" -NotePropertyValue $inputIndex -Force
                        $inputIndex++
                        
                        # Add silent audio for image
                        $arguments += "-f lavfi -t $($highlight.duration) -i anullsrc=channel_layout=stereo:sample_rate=48000 "
                        $highlight | Add-Member -NotePropertyName "audioIndex" -NotePropertyValue $inputIndex -Force
                        $inputIndex++
                    }
                    else {
                        # Video clips use source video [0]
                        $highlight | Add-Member -NotePropertyName "inputIndex" -NotePropertyValue 0 -Force
                    }
                }
                
                # Check if end screen image exists and add as input
                $endScreenImage = $PSScriptRoot + "\resources\EndScreenBackground.JPG"
                $hasEndScreen = Test-Path $endScreenImage
                
                $musicInputIndex = -1
                if($hasEndScreen) {
                    # Add end screen image as input with audio null source
                    $arguments += "-loop 1 -framerate 29.97 -t 5 -i " + [char]34 + $endScreenImage + [char]34 + " -f lavfi -t 5 -i anullsrc=channel_layout=stereo:sample_rate=48000 "
                    $endScreenInputIndex = $inputIndex
                    $endScreenAudioIndex = $inputIndex + 1
                    $inputIndex += 2
                }
                
                # Add background music if enabled
                if($BackgroundMusic -ne $null -and (Test-Path $BackgroundMusic.FilePath)) {
                    $arguments += "-stream_loop -1 -i " + [char]34 + $BackgroundMusic.FilePath + [char]34 + " "
                    $musicInputIndex = $inputIndex
                    write-host "Background music added as input index: $musicInputIndex"
                }
                
                $arguments += "-filter_complex " + [char]34
                
                #ffmpeg.exe -i D:\Insta360Parts\20221016-Full.mp4 -filter_complex "[0]atrim=3:12,asetpts=PTS-STARTPTS[ap1],[0]trim=3:12,setpts=PTS-STARTPTS[p1],[0]atrim=600:620,asetpts=PTS-STARTPTS[ap2],[0]trim=600:620,setpts=PTS-STARTPTS[p2],[p1][ap1][p2][ap2]
                #concat=n=2:v=1:a=1[out][aout]" -map "[out]" -map "[aout]" D:\test.mp4 -hwaccel cuda -hwaccel_output_format cuda -y
                $cut = ""
                $concat = ""
                for ($i = 0; $i -lt $Highlights.Count; $i++) 
                {
                    $highlight = $Highlights[$i]
                    
                    if($highlight.type -eq "picture") {
                        # Picture highlight processing
                        $inputIdx = $highlight.inputIndex
                        $audioIdx = $highlight.audioIndex
                        
                        # Escape comment for drawtext
                        if($highlight.Comment -ne $null -and $highlight.Comment.Trim() -ne "") {
                            $escapedComment = $highlight.Comment
                            $escapedComment = $escapedComment -replace ":", " -"
                            $escapedComment = $escapedComment -replace "'", ""
                            $escapedComment = $escapedComment -replace "\\", ""
                            $escapedComment = $escapedComment -replace "\|", ""
                            $escapedComment = $escapedComment -replace ";", ","
                            $commentFilter = ",drawtext=text='" + $escapedComment + "':fontcolor=white:fontsize=130:x=(w-tw)/2:y=h-(2*lh):font=Arial Black"
                        }
                        else {
                            $commentFilter = ""
                        }
                        
                        # Build filter for image: scale, pad, format, optional text overlay with black border
                        if($highlight.Comment -ne $null -and $highlight.Comment.Trim() -ne "") {
                            $escapedComment = $highlight.Comment
                            $escapedComment = $escapedComment -replace ":", " -"
                            $escapedComment = $escapedComment -replace "'", ""
                            $escapedComment = $escapedComment -replace "\\", ""
                            $escapedComment = $escapedComment -replace "\|", ""
                            $escapedComment = $escapedComment -replace ";", ","
                            $commentFilter = ",drawtext=text='" + $escapedComment + "':fontcolor=white:fontsize=130:borderw=5:bordercolor=black:x=(w-tw)/2:y=h-(2*lh):font=Arial Black"
                        }
                        else {
                            $commentFilter = ""
                        }
                        
                        $cut += "[$inputIdx]scale=${videoWidth}:${videoHeight}:force_original_aspect_ratio=decrease,pad=${videoWidth}:${videoHeight}:(ow-iw)/2:(oh-ih)/2:black,setsar=1:1${commentFilter},format=yuv420p,setpts=PTS-STARTPTS[p$i],[$audioIdx]asetpts=PTS-STARTPTS[ap$i],"
                        $concat += "[p$i][ap$i]"
                    }
                    else {
                        # Video highlight processing (existing logic)
                        # Adding Comment if one is Available with black border for readability
                        if($highlight.Comment -ne $null -and $highlight.Comment.Trim() -ne "")
                        {
                            # Escape special characters for ffmpeg drawtext filter
                            $escapedComment = $highlight.Comment
                            # Remove or replace problematic characters
                            $escapedComment = $escapedComment -replace ":", " -"  # Replace colon with dash
                            $escapedComment = $escapedComment -replace "'", ""    # Remove single quotes
                            $escapedComment = $escapedComment -replace "\\", ""   # Remove backslashes
                            $escapedComment = $escapedComment -replace "\|", ""   # Remove pipes
                            $escapedComment = $escapedComment -replace ";", ","   # Replace semicolons
                            $Comment=",drawtext=text='" + $escapedComment + "':fontcolor=white:fontsize=130:borderw=5:bordercolor=black:x=(w-tw)/2:y=h-(2*lh):font=Arial Black"
                        }
                        else 
                        {
                            $Comment = $null
                        }
                        $cut += "[0]atrim=" + $highlight.start + ":" + $highlight.end + ",asetpts=PTS-STARTPTS[ap" + $i + "],[0]trim=" + $highlight.start + ":" + $highlight.end + $Comment + ",setpts=PTS-STARTPTS[p"+ $i + "],"
                        $concat += "[p" + $i +"][ap" + $i + "]"
                    }
                }
                
                if($hasEndScreen) {
                    # Add end screen to filter chain with matching SAR
                    $endScreenIndex = $Highlights.Count
                    $cut += "[$endScreenInputIndex]scale=${videoWidth}:${videoHeight}:force_original_aspect_ratio=decrease,pad=${videoWidth}:${videoHeight}:(ow-iw)/2:(oh-ih)/2:black,setsar=1:1," +
                        "drawtext=text='Danke, bis bald!':fontcolor=white:fontsize=80:x=(w-tw)/2:y=(h-th)/2-40:font=Arial Black," +
                        "drawtext=text='Like & Subscribe':fontcolor=white:fontsize=60:x=(w-tw)/2:y=(h-th)/2+60:font=Arial,format=yuv420p,setpts=PTS-STARTPTS[p" + $endScreenIndex + "],[$endScreenAudioIndex]asetpts=PTS-STARTPTS[ap" + $endScreenIndex + "],"
                    $concat += "[p" + $endScreenIndex + "][ap" + $endScreenIndex + "]"
                    
                    if($musicInputIndex -ge 0) {
                        # Mix background music with video audio using overlay percentages
                        # MusicVolume = overlay percentage (e.g., 0.4 for 40% music)
                        # OriginalVolume = 1 - overlay percentage (e.g., 0.6 for 60% original)
                        $musicVol = $BackgroundMusic.MusicVolume
                        $origVol = $BackgroundMusic.OriginalVolume
                        $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count + 1) + ":v=1:a=1[out][aout];[aout]volume=" + $origVol + "[orig];[$musicInputIndex]volume=" + $musicVol + "[music];[orig][music]amix=inputs=2:duration=first:dropout_transition=2[finalout]" + [char]34 + " -map " + [char]34 + "[out]" + [char]34 + " -map " + [char]34 + "[finalout]" + [char]34 + " -c:v h264_nvenc -preset p4 -b:v 20M -c:a aac -b:a 192k " + $OutputPath + " -y"
                    } else {
                        $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count + 1) + ":v=1:a=1[out][aout]"+ [char]34 + " -map " + [char]34 + "[out]" + [char]34 +" -map " + [char]34 + "[aout]" + [char]34 + " -c:v h264_nvenc -preset p4 -b:v 20M -c:a aac -b:a 192k " + $OutputPath + " -y"
                    }
                } else {
                    if($musicInputIndex -ge 0) {
                        # Mix background music with video audio using overlay percentages
                        $musicVol = $BackgroundMusic.MusicVolume
                        $origVol = $BackgroundMusic.OriginalVolume
                        $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count) + ":v=1:a=1[out][aout];[aout]volume=" + $origVol + "[orig];[$musicInputIndex]volume=" + $musicVol + "[music];[orig][music]amix=inputs=2:duration=first:dropout_transition=2[finalout]" + [char]34 + " -map " + [char]34 + "[out]" + [char]34 + " -map " + [char]34 + "[finalout]" + [char]34 + " -c:v h264_nvenc -preset p4 -b:v 20M -c:a aac -b:a 192k " + $OutputPath + " -y"
                    } else {
                        $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count) + ":v=1:a=1[out][aout]"+ [char]34 + " -map " + [char]34 + "[out]" + [char]34 +" -map " + [char]34 + "[aout]" + [char]34 + " -c:v h264_nvenc -preset p4 -b:v 20M -c:a aac -b:a 192k " + $OutputPath + " -y"
                    }
                }

                write-host $arguments
                $process = start-process -FilePath $ffmpeg -ArgumentList $arguments -PassThru -wait -nonewWindow
                
                if($process.ExitCode -ne 0) {
                    write-host "FFmpeg process failed with exit code: $($process.ExitCode)" -ForegroundColor Red
                    return $false
                }
            }
    
    end 
    {
        start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + $OutputPath) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\length.txt -PassThru -Wait | Out-Null
        $SourceVideoLength = (get-content C:\Windows\Temp\length.txt).Split(".")[0]
        write-host ("Output Video Length: " + $SourceVideoLength)   
    }
}