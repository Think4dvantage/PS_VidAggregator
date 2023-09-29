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
        $ffprobe = $PSScriptRoot + "\ffmpeg\ffmpeg-master-latest-win64-gpl\bin\ffprobe.exe"
        #Checking if FFMPEG is present
        if(!(test-path $ffmpeg))
        {
            $ffmpegDL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
            Invoke-WebRequest -Uri $ffmpegDL -OutFile ".\ffmpeg.zip"
            Expand-archive -Path ".\ffmpeg.zip" -DestinationPath ".\ffmpeg\"
            remove-item -path ".\ffmpeg.zip" -Force -Recurse
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
                if ($inputPart.start -ge $part.start -and $inputPart.start -le $part.end -and $inputPart.end -ge $part.start -and $inputPart.end -le $part.end) {
                    write-host ("Input " + $InputPart + " was too close - skipping")
                    continue
                }
                else {
        
                    if (($OutputLength - $provLength ) -le $partLength) 
                    {
                        for ($i = 0; $i -lt $partLength; $i++) {
                            $Highlights[$i].End = $Highlights[$i].end + 1
                            if((calc-partLength $Highlights) -eq $OutputLength)
                            {
                                break
                            }
                        }
                    }
                }
            }
            $Highlights += $inputPart
            $provLength = calc-partLength $Highlights
        } while (
            $provLength -le $OutputLength
        )
        write-host "We got out of the Loop"
        $Highlights = ($Highlights | sort-object start)
        write-host $Highlights
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
                $arguments += $cut + $concat + "concat=n=" + ($Highlights.Count) + ":v=1:a=1[out][aout]"+ [char]34 + " -map " + [char]34 + "[out]" + [char]34 +" -map " + [char]34 + "[aout]" + [char]34 + " " + $OutputPath + " -y"

                write-host $arguments
                start-process -FilePath $ffmpeg -ArgumentList $arguments -PassThru -wait -nonewWindow
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

#$Highlights = @([PSCustomObject]@{start=9; end=19}, [PSCustomObject]@{start=22; end=32}, [PSCustomObject]@{start=1110; end=1121}, [PSCustomObject]@{start=1150; end=1160},[PSCustomObject]@{start=2225; end= 2235})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-04-02-FullFlight.mp4" -Highlights $Highlights -OutputLength 180 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-04-02-Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=10}, [PSCustomObject]@{start=17; end=25}, [PSCustomObject]@{start=817; end=830}, [PSCustomObject]@{start=970; end=980}, [PSCustomObject]@{start=1148; end=1158}, [PSCustomObject]@{start=2190; end=2200}, [PSCustomObject]@{start=3720; end=3735})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-04-05-FullFlight.mp4" -Highlights $Highlights -OutputLength 200 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-04-05-Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=8}, [PSCustomObject]@{start=21; end=28},[PSCustomObject]@{start=80; end=95},[PSCustomObject]@{start=1925; end=1933},[PSCustomObject]@{start=1910; end=1915},[PSCustomObject]@{start=2080; end=2090},[PSCustomObject]@{start=2110; end=2120})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-04-06-FullFlight.mp4" -Highlights $Highlights -OutputLength 160 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-04-06-Short.mp4"

#$Highlights = @([PSCustomObject]@{start=87; end=105}, [PSCustomObject]@{start=8392; end=8421})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-04-09-FullFlight.mp4" -Highlights $Highlights -OutputLength 240 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-04-09-Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=10}, [PSCustomObject]@{start=1175; end=1190})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-04-17-FullFlight.mp4" -Highlights $Highlights -OutputLength 150 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-04-17-Short.mp4"

#$Highlights = @([PSCustomObject]@{start=14; end=25}, [PSCustomObject]@{start=47; end=57}, [PSCustomObject]@{start=1538; end=1543}, [PSCustomObject]@{start=2322; end=2328}, [PSCustomObject]@{start=2520; end=2537})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-04-26_FullFlight.mp4" -Highlights $Highlights -OutputLength 200 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-04-26_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=10}, [PSCustomObject]@{start=52; end=73}, [PSCustomObject]@{start=1902; end=1908}, [PSCustomObject]@{start=2891; end=2896}, [PSCustomObject]@{start=3995; end=4000}, [PSCustomObject]@{start=4740; end=4751})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-05-06_FullFlight.mp4" -Highlights $Highlights -OutputLength 180 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-05-06_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=10}, [PSCustomObject]@{start=244; end=254}, [PSCustomObject]@{start=290; end=300}, [PSCustomObject]@{start=444; end=454}, [PSCustomObject]@{start=2160; end=2177})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-05-19_FullFlight.mp4" -Highlights $Highlights -OutputLength 179 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-05-19_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=20; end=30}, [PSCustomObject]@{start=1260; end=1273})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-05-20-FullFlight.mp4" -Highlights $Highlights -OutputLength 119 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-05-20_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=60; end=66}, [PSCustomObject]@{start=996; end=1001}, [PSCustomObject]@{start=2021; end=2026}, [PSCustomObject]@{start=2021; end=2026}, [PSCustomObject]@{start=3798; end=3808}, [PSCustomObject]@{start=4385; end=4400})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-05-21_FullFlight.mp4" -Highlights $Highlights -OutputLength 239 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-05-21_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=6}, [PSCustomObject]@{start=1510; end=1520}, [PSCustomObject]@{start=2022; end=2040}, [PSCustomObject]@{start=5720; end=5730})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-05-26_FullFlight.mp4" -Highlights $Highlights -OutputLength 299 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-05-26_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=6}, [PSCustomObject]@{start=88; end=100}, [PSCustomObject]@{start=109; end=120}, [PSCustomObject]@{start=700; end=715}, [PSCustomObject]@{start=3030; end=3041})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-05-28_FullFlight.mp4" -Highlights $Highlights -OutputLength 179 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-05-28_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=10}, [PSCustomObject]@{start=3420; end=3427})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-05-29_FullFlight.mp4" -Highlights $Highlights -OutputLength 179 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-05-29_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=14}, [PSCustomObject]@{start=1800; end=1810}, [PSCustomObject]@{start=1950; end=2000})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-06-02_FullFlight.mp4" -Highlights $Highlights -OutputLength 119 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-06-02_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=5; end=15}, [PSCustomObject]@{start=608; end=612}, [PSCustomObject]@{start=780; end=795})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-06-05_FullFlight.mp4" -Highlights $Highlights -OutputLength 89 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-06-05_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=0; end=10}, [PSCustomObject]@{start=2460; end=2465}, [PSCustomObject]@{start=2471; end=2476}, [PSCustomObject]@{start=6380; end=6385}, [PSCustomObject]@{start=9010; end=9022})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-06-09_FullFlight.mp4" -Highlights $Highlights -OutputLength 209 -PartLength 5 -OutputPath "D:6\Insta360Parts\2023-06-09_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=21; end=35}, [PSCustomObject]@{start=1010; end=1025}, [PSCustomObject]@{start=4440; end=4455})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-06-17_FullFlight.mp4" -Highlights $Highlights -OutputLength 119 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-06-17_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=7; end=19}, [PSCustomObject]@{start=725; end=740})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-06-21_FullFlight.mp4" -Highlights $Highlights -OutputLength 88 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-06-21_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=13; end=20}, [PSCustomObject]@{start=227; end=237}, [PSCustomObject]@{start=383; end=393}, [PSCustomObject]@{start=809; end=819}, [PSCustomObject]@{start=1042; end=1050}, [PSCustomObject]@{start=2958; end=2963}, [PSCustomObject]@{start=3465; end=3474})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-06-25_FullFlight.mp4" -Highlights $Highlights -OutputLength 145 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-06-25_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=13; end=20}, [PSCustomObject]@{start=300; end=311}, [PSCustomObject]@{start=775; end=785}, [PSCustomObject]@{start=792; end=802}, [PSCustomObject]@{start=1410; end=1420})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-07-23_FD.mp4" -Highlights $Highlights -OutputLength 145 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-07-23_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=5; end=14}, [PSCustomObject]@{start=965; end=974})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-07-27_FullFlight.mp4" -Highlights $Highlights -OutputLength 120 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-07-27_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=3; end=15}, [PSCustomObject]@{start=1558; end=1570})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-07-31_FullFlight.mp4" -Highlights $Highlights -OutputLength 120 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-07-31_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=3; end=10}, [PSCustomObject]@{start=4385; end=4394})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-08-11_FullFlight.mp4" -Highlights $Highlights -OutputLength 150 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-08-11_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=4; end=15}, [PSCustomObject]@{start=744; end=754})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-08-12_FullFlight.mp4" -Highlights $Highlights -OutputLength 100 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-08-12_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=3; end=13}, [PSCustomObject]@{start=802; end=810})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-08-13_FullFlight.mp4" -Highlights $Highlights -OutputLength 100 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-08-13_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=10; end=18}, [PSCustomObject]@{start=926; end=933})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-08-15_FullFlight.mp4" -Highlights $Highlights -OutputLength 100 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-08-15_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=2; end=12}, [PSCustomObject]@{start=737; end=751})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-08-18_FullFlight.mp4" -Highlights $Highlights -OutputLength 120 -PartLength 6 -OutputPath "D:\Insta360Parts\2023-08-18_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=24; end=34}, [PSCustomObject]@{start=6374; end=6384}, [PSCustomObject]@{start=9400; end=9410}, [PSCustomObject]@{start=11487; end=11497}, [PSCustomObject]@{start=12390; end=12403})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-08-19_FullFlight.mp4" -Highlights $Highlights -OutputLength 220 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-08-19_Short.mp4"

#$Highlights = @([PSCustomObject]@{start=24; end=34}, [PSCustomObject]@{start=6374; end=6384}, [PSCustomObject]@{start=9400; end=9410}, [PSCustomObject]@{start=11487; end=11497}, [PSCustomObject]@{start=12390; end=12403})
#aggregate-Video -SourceVideo "D:\Insta360Parts\2023-08-19_FullFlight.mp4" -Highlights $Highlights -OutputLength 220 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-08-19_Short.mp4"

$Highlights = @([PSCustomObject]@{start=7; end=15}, [PSCustomObject]@{start=1068; end=1076})
aggregate-Video -SourceVideo "D:\Insta360Parts\2023-09-20_FullFlight1.mp4" -Highlights $Highlights -OutputLength 220 -PartLength 5 -OutputPath "D:\Insta360Parts\2023-09-20_-Short1.mp4"