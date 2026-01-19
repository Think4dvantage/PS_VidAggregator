function Concatenate-Video {
    [CmdletBinding()]
    param (
        [array]$VideoParts,
        [boolean]$deleteParts=$false,
        [string]$Output,
        [string]$TempVidFile="C:\Windows\Temp\VidParts.txt"
    )
    
    begin 
    {
        #Creating Temporary VidParts File
        New-Item -Path $TempVidFile -Force | Out-Null

        # Ensure FFmpeg is installed and up-to-date
        . "$PSScriptRoot\PrereqManager.ps1"
        $ffmpegPaths = Ensure-FFmpeg
        $ffmpeg = $ffmpegPaths.FFmpeg
    }
    
    process 
    {
        foreach($video in $VideoParts)
        {  
            #Structure of PartInput
            #file 'D:\Insta360Parts\VID_20230122_FullFlightP1.mp4'
            #file 'D:\Insta360Parts\VID_20230122_FullFlightP2.mp4'
            add-content -Path $TempVidFile -Value ("file " + [char]39 + $video + [char]39)
        }
        #run Concatenation
        start-process -FilePath $ffmpeg -ArgumentList ("-f concat -safe 0 -i " + $TempVidFile + " -c copy " + $Output +" -y") -PassThru -Wait -NoNewWindow
    }
    
    end {
        if((test-path -path $output) -and (get-childitem -path $output).length -gt 2000 -and $deleteParts -eq $true)
        {
            foreach($video in $VideoParts)
            {
                Remove-item -path $video -force 
            }
        }
        remove-item -path $TempVidFile -Force
    }
}