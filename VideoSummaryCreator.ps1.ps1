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
        $ffmpeg = $PSScriptRoot + "\ffmpeg\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe"
        $ffprobe = $PSScriptRoot + "\ffmpeg\ffmpeg-master-latest-win64-gpl\bin\ffprobe.exe.exe"
        #Checking if FFMPEG is present
        if(!(test-path $ffmpeg))
        {
            $ffmpegDL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
            Invoke-WebRequest -Uri $ffmpegDL -OutFile ".\ffmpeg.zip"
            Expand-archive -Path ".\ffmpeg.zip" -DestinationPath ".\ffmpeg\"
        }

        start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + $SourceVideoPath) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\length.txt -PassThru -Wait | Out-Null
        $SourceVideoLength = (get-content C:\Windows\Temp\length.txt).Split(".")[0]
        write-host ("Source Video Length: " + $SourceVideoLength)

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
        $Increment = [int]($SourceVideoLength / $addparts)
        write-host ("Increment is: " + $Increment)
        $start = 0
        $end = 0
        write-host $Highlights
        do {
            $start = $start + $Increment
            $end = $start + $PartLength
            if($end -ge $SourceVideoLength)
            {
                $Highlights = $Highlights | sort-object start
                $provLength = calc-partLength $Highlights
                write-host ("Highest Part length has been reached still " + ($OutputLength - $provLength).toString() + " Seconds missing. Adding to each part")
                for ($i = 0; $i -lt ($Highlights.Count -1); $i++) {
                    write-host $i
                    $Highlights[$i].end = $Highlights[$i].end + 1
                    if((calc-partLength $Highlights) -eq $OutputLength)
                    {
                        break
                    }
                }
                break
            }
            $inputPart = ([PSCustomObject]@{start=$start; end=$end})
            foreach ($part in $Highlights) {
                if ($inputPart.start -in ($part.start..$part.end) -and $inputPart.end -in ($part.start..$part.end)) {
                    write-host ("Input " + $InputPart + " was too close - skipping")
                    continue
                }
                else {
        
                    if (($OutputLength - $provLength ) -le $partLength) 
                    {
                        $tempLength = $OutputLength - $provLength
                        $InputPart = [PSCustomObject]@{start=$start; end=($start + $TempLength)}
                        $Highlights += $inputPart
                        write-host "should be at the end"
                        break
                    }
                }
            }
            $Highlights += $inputPart
            $provLength = calc-partLength $Highlights
        } while (
            $provLength -le $OutputLength
        )
        write-host "We got out of the Loop"
        write-host ($Highlights | sort-object start )
        write-host ( $provLength = calc-partLength $Highlights)
        
    }
    
    process {
                #ffmpeg.exe -i D:\Insta360Parts\20221016-Full.mp4 -filter_complex "[0]atrim=3:12,asetpts=PTS-STARTPTS[ap1],[0]trim=3:12,setpts=PTS-STARTPTS[p1],[0]atrim=600:620,asetpts=PTS-STARTPTS[ap2],[0]trim=600:620,setpts=PTS-STARTPTS[p2],[p1][ap1][p2][ap2]
                #concat=n=2:v=1:a=1[out][aout]" -map "[out]" -map "[aout]" D:\test.mp4 -hwaccel cuda -hwaccel_output_format cuda -y
                $arguments = "-i " + $SourceVideoPath + " -filter_complex " + [char]34
                $cut = ""
                $concat = ""
                for ($i = 0; $i -lt $Highlights.Count; $i++) 
                {
                    $cut += "[0]atrim=" + $Highlights[$i].start + ":" + $Highlights[$i].end + ",asetpts=PTS-STARTPTS[ap" + $i + "],[0]trim=" + $Highlights[$i].start + ":" + $Highlights[$i].end + ",setpts=PTS-STARTPTS[p"+ $i + "],"
                    $concat += "[p" + $i +"][ap" + $i + "]"
                }
                $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count) + ":v=1:a=1[out][aout]"+ [char]34 + " -map " + [char]34 + "[out]" + [char]34 +" -map " + [char]34 + "[aout]" + [char]34 + " " + $OutputPath + " -hwaccel cuda -hwaccel_output_format cuda -y"

                write-host $arguments
                start-process -FilePath "C:\git\GleitschirmVideoCreator\ffmpeg\ffmpeg.exe" -ArgumentList $arguments -PassThru -wait -nonewWindow
            }
    
    end 
    {
        start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + $OutputPath) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\length.txt -PassThru -Wait | Out-Null
        $SourceVideoLength = (get-content C:\Windows\Temp\length.txt).Split(".")[0]
        write-host ("Output Video Length: " + $SourceVideoLength)   
    }
}

#$Highlights = @([PSCustomObject]@{start=0; end=14}, [PSCustomObject]@{start=466; end=488},[PSCustomObject]@{start=1090; end=1100} , [PSCustomObject]@{start=1200; end=1190}, [PSCustomObject]@{start=1906; end=1919},[PSCustomObject]@{start=1920; end=1930})
#aggregate-Video -SourceVideo "D:\Insta360Parts\VID_20230305_Flight1.mp4" -Highlights $Highlights -OutputLength 120 -PartLength 10 -OutputPath "D:\Insta360Parts\2023-03-05_Flight1-Short.mp4"

$Highlights = @([PSCustomObject]@{start=885; end=900}, [PSCustomObject]@{start=1270; end=1280}, [PSCustomObject]@{start=1785; end=1795}, [PSCustomObject]@{start=3300; end=3320})
aggregate-Video -SourceVideo "D:\Insta360Parts\VID_20230305_Flight2.mp4" -Highlights $Highlights -OutputLength 180 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-03-05_Flight2-Short.mp4"