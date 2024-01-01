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

$ShortsList = get-childitem -path "D:\Insta360Parts" | where-object Name -like "*_SH-*.mp4"

foreach($short in $ShortsList)
{
    start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + ($short.VersionInfo.FileName)) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\length.txt -PassThru -Wait | Out-Null
    $SVL = (get-content C:\Windows\Temp\length.txt).Split(".")[0]
    if($SVL -gt 20)
    {
        $parts = @()
        if($SVL -lt 30)
        {
            [int]$pl = $SVL / 2
            $parts += [PSCustomObject]@{start=00; len=$pl.toString()}
            $parts += [PSCustomObject]@{start=$pl.toString(); len=($pl.toString())}
        }    
        elseif($SVL -lt 45)
        {
            [int]$pl = $SVL / 3
            $parts += [PSCustomObject]@{start=00; len=$pl.toString()}
            $parts += [PSCustomObject]@{start=$pl.toString(); len=$pl.toString()}
            $parts += [PSCustomObject]@{start=($pl*2).toString(); len=($pl.toString())}
        }
        else 
        {
            [int]$pl = $SVL / 4
            $parts += [PSCustomObject]@{start=00; len=$pl.toString()}
            $parts += [PSCustomObject]@{start=$pl.toString(); len=$pl.toString()}
            $parts += [PSCustomObject]@{start=($pl*2).toString(); len=$pl.toString()}
            $parts += [PSCustomObject]@{start=($pl*3).toString(); len=($pl.toString())}
        }   
        
        foreach($part in $parts)
        {
            if($part.start.Length -lt 2)
            {
                $part.start = "0" + $part.start
            }

            if($part.len.Length -lt 2)
            {
                $part.len = "0" + $part.len
            }

            $arguments = "-i " + $short.VersionInfo.FileName + " -ss 00:00:" + $part.start + " -t 00:00:" + $part.len + " -c:v copy -c:a copy " + ($short.VersionInfo.FileName).Replace(".mp4",(get-date).second.toString() + ".mp4") 
            write-host $arguments
            start-process -FilePath $ffmpeg -ArgumentList $arguments -PassThru -wait -nonewWindow
        }
        
    }


#ffmpeg.exe -i D:\Insta360Parts\20221016-Full.mp4 -filter_complex "[0]atrim=3:12,asetpts=PTS-STARTPTS[ap1],[0]trim=3:12,setpts=PTS-STARTPTS[p1],[0]atrim=600:620,asetpts=PTS-STARTPTS[ap2],[0]trim=600:620,setpts=PTS-STARTPTS[p2],[p1][ap1][p2][ap2]






}


