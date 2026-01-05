function aggregate-Video {
    [CmdletBinding()]
    param (
        [string]$SourceVideoPath,
        [array]$Highlights,
        [int]$OutputLength,
        [int]$PartLength,
        [string]$OutputPath 
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
            foreach($prt in $hl)
            {
                $tmplngth += $prt.end - $prt.start
            }
            return $tmplngth
        }

        $provLength = 0 
        foreach ($part in $Highlights) {
            if ($part.start -gt $part.end) {
                write-host ("You IDIOT the start of the Highlight is bigger than the end: Removing this! BASTARD!")
                $Highlights = $Highlights | where-object {$_.start -ne $part.start -and $_.end -ne $part.end}
            }
            elseif($part.start -ge $SourceVideoLength -or $part.end -gt $SourceVideoLength)
            {
                $Highlights = $Highlights | where-object {$_.start -ne $part.start -and $_.end -ne $part.end}
                write-host "Removing part that is bigger than the actual Length of Video"
            }

            $provLength = calc-partLength $Highlights
        }
        $LeftoverOutputLength = $OutputLength - $provLength
        write-host ("Video Length left after Highlights: " + $LeftoverOutputLength)
        $addParts = [int]($LeftoverOutputLength / $PartLength)
        write-host ("Parts to add after Highlight:" + $addParts)
        
        # Find the last highlight end time to avoid adding parts after it
        $Highlights = $Highlights | sort-object start
        $lastHighlightEnd = ($Highlights | Measure-Object -Property end -Maximum).Maximum
        write-host ("Last highlight ends at: " + $lastHighlightEnd)
        
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
            $inputPart = ([PSCustomObject]@{start=$start; end=$end})
            $Highlights = ($Highlights | sort-object start)
            
            # Check if the new part overlaps with any existing highlight
            $hasOverlap = $false
            foreach ($part in $Highlights) {
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
                $Highlights += $inputPart
                write-host ("Added part: $($inputPart.start)-$($inputPart.end)")
            }
            
            $provLength = calc-partLength $Highlights
            
            # If we're close to the target length, extend existing parts instead of adding more
            if (($OutputLength - $provLength) -le $partLength -and ($OutputLength - $provLength) -gt 0) {
                $i = 0
                while ($provLength -lt $OutputLength -and $i -lt $Highlights.Count) {
                    $Highlights[$i].End = $Highlights[$i].end + 1
                    $provLength = calc-partLength $Highlights
                    $i++
                }
            }
        } while (
            $provLength -le $OutputLength
        )
        $Highlights = ($Highlights | sort-object start)
        
    }
    
    process {
                # Check if end screen image exists and add as input
                $endScreenImage = $PSScriptRoot + "\resources\EndScreenBackground.JPG"
                $hasEndScreen = Test-Path $endScreenImage
                
                if($hasEndScreen) {
                    # Add end screen image as second input with audio null source
                    $arguments = "-i " + $SourceVideoPath + " -loop 1 -framerate 29.97 -t 5 -i " + [char]34 + $endScreenImage + [char]34 + " -f lavfi -t 5 -i anullsrc=channel_layout=stereo:sample_rate=48000 -filter_complex " + [char]34
                } else {
                    $arguments = "-i " + $SourceVideoPath + " -filter_complex " + [char]34
                }
                
                #ffmpeg.exe -i D:\Insta360Parts\20221016-Full.mp4 -filter_complex "[0]atrim=3:12,asetpts=PTS-STARTPTS[ap1],[0]trim=3:12,setpts=PTS-STARTPTS[p1],[0]atrim=600:620,asetpts=PTS-STARTPTS[ap2],[0]trim=600:620,setpts=PTS-STARTPTS[p2],[p1][ap1][p2][ap2]
                #concat=n=2:v=1:a=1[out][aout]" -map "[out]" -map "[aout]" D:\test.mp4 -hwaccel cuda -hwaccel_output_format cuda -y
                $cut = ""
                $concat = ""
                for ($i = 0; $i -lt $Highlights.Count; $i++) 
                {
                    #Adding Comment if one is Available
                    if($Highlights[$i].Comment -ne $null -and $Highlights[$i].Comment.Trim() -ne "")
                    {
                        # Escape special characters for ffmpeg drawtext filter
                        $escapedComment = $Highlights[$i].Comment
                        # Remove or replace problematic characters
                        $escapedComment = $escapedComment -replace ":", " -"  # Replace colon with dash
                        $escapedComment = $escapedComment -replace "'", ""    # Remove single quotes
                        $escapedComment = $escapedComment -replace "\\", ""   # Remove backslashes
                        $escapedComment = $escapedComment -replace "\|", ""   # Remove pipes
                        $escapedComment = $escapedComment -replace ";", ","   # Replace semicolons
                        $Comment=",drawtext=text='" + $escapedComment + "':fontcolor=white:fontsize=130:x=(w-tw)/2: y=h-(2*lh):font=Arial Black"
                    }
                    else 
                    {
                        $Comment = $null
                    }
                    $cut += "[0]atrim=" + $Highlights[$i].start + ":" + $Highlights[$i].end + ",asetpts=PTS-STARTPTS[ap" + $i + "],[0]trim=" + $Highlights[$i].start + ":" + $Highlights[$i].end + $Comment + ",setpts=PTS-STARTPTS[p"+ $i + "],"
                    $concat += "[p" + $i +"][ap" + $i + "]"
                }
                
                if($hasEndScreen) {
                    # Add end screen to filter chain with matching SAR
                    $endScreenIndex = $Highlights.Count
                    $cut += "[1]scale=3840:2160:force_original_aspect_ratio=decrease,pad=3840:2160:(ow-iw)/2:(oh-ih)/2:black,setsar=1:1," +
                        "drawtext=text='Danke, bis bald!':fontcolor=white:fontsize=80:x=(w-tw)/2:y=(h-th)/2-40:font=Arial Black," +
                        "drawtext=text='Like & Subscribe':fontcolor=white:fontsize=60:x=(w-tw)/2:y=(h-th)/2+60:font=Arial,format=yuv420p,setpts=PTS-STARTPTS[p" + $endScreenIndex + "],[2]asetpts=PTS-STARTPTS[ap" + $endScreenIndex + "],"
                    $concat += "[p" + $endScreenIndex + "][ap" + $endScreenIndex + "]"
                    $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count + 1) + ":v=1:a=1[out][aout]"+ [char]34 + " -map " + [char]34 + "[out]" + [char]34 +" -map " + [char]34 + "[aout]" + [char]34 + " -c:v h264_nvenc -preset p4 -b:v 20M -c:a aac -b:a 192k " + $OutputPath + " -y"
                } else {
                    $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count) + ":v=1:a=1[out][aout]"+ [char]34 + " -map " + [char]34 + "[out]" + [char]34 +" -map " + [char]34 + "[aout]" + [char]34 + " -c:v h264_nvenc -preset p4 -b:v 20M -c:a aac -b:a 192k " + $OutputPath + " -y"
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