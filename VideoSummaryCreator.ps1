function create-Summary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage="Path to FFMPEG.exe",ValueFromPipeline=$true)][string]$ffmpegPath,
        [Parameter(Mandatory=$true,HelpMessage="Path to input Video",ValueFromPipeline=$true)][string]$VideoPath,
        [Parameter(Mandatory=$true,HelpMessage="Path to where the Output should end",ValueFromPipeline=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true,HelpMessage="Seconds from the Start of Video when Launch Starts",ValueFromPipeline=$true)][int]$LaunchBegin,
        [Parameter(Mandatory=$true,HelpMessage="Seconds from the Start of Video when Launch Ends",ValueFromPipeline=$true)][int]$LaunchEnd,
        [Parameter(Mandatory=$true,HelpMessage="Seconds from the Start of Video when Landing Starts",ValueFromPipeline=$true)][int]$LandingBegin,
        [Parameter(Mandatory=$true,HelpMessage="Seconds from the Start of Video when Landing Ends",ValueFromPipeline=$true)][int]$LandingEnd,
        [Parameter(Mandatory=$true,HelpMessage="Value in Seconds on how Long the Resulting Video should be",ValueFromPipeline=$true)][int]$VideoLength,
        [Parameter(Mandatory=$true,HelpMessage="Length of short Video Parts used for Summary",ValueFromPipeline=$true)][int]$IncLength,
        [Parameter(Mandatory=$true,HelpMessage="Array filled with start/End hashtable Videoparts",ValueFromPipeline=$true)][array]$InputParts
        
        
    )
    
    begin 
    {
        #Check for ffmpeg in path
        if(!($ffmpegPath -like "*ffmpeg.exe"))
        {
            write-error "you need to provide a Path to the ffmpeg.exe including the ffmpeg.exe"
        }

        #Test FFMPEG Path
        if(!(test-path $ffmpegpath))
        {
            write-error "Path to ffmpeg does not work. Please download FFMPEG and provide a Parth to the EXE"
        }

        #Calculate length of the Source Video from Launch Start to LandingEnd
        $SourceLength = $LandingBegin-$LaunchEnd
        write-host ("SourceLength = " + $SourceLength)

        $LengthOfSurroundings = ($LandingEnd - $LandingBegin) + ($LaunchEnd - $LaunchBegin)
        write-host ("LengthOfSurroundings = " +  $LengthOfSurroundings)

        #IncrementLength
        $IncSize = $SourceLength - $LengthOfSurroundings
        write-host ("IncSize "+ $IncSize)
        
        #Calculate Count of Parts needed for video length
        [int]$PartCount = $VideoLength/$IncLength
        write-Host ("Partcount = " + $Partcount)

        #Time fulfiller
        [int]$LastPartInc = $IncSize - ($Partcount * $IncLength)

        #IncDistance = 
        [int]$IncDist = $IncSize / ($partcount + 2)
        write-host ("IncDist = " + $IncDist)
        
    }
    
    process 
    {
        $parts = @(@{Start=$LaunchBegin;End=$LaunchEnd},@{Start=$LandinBegin;End=$LandingEnd})
        

        #Prepare first Part of Command with Launch
        $FFMPEGCommand = "-i $VideoPath -filter_complex " + [char]34 + "[0]atrim=" + $LaunchBegin + ":" + $LaunchEnd + ",asetpts=PTS-STARTPTS[ap1],[0]trim=" + $LaunchBegin + ":" + $LaunchEnd + ",setpts=PTS-STARTPTS[p1],"
        $CommandMid = "[p1][ap1]"
        $cursor = $LaunchEnd + $IncDist
        $i = 0
        #Incrementing trough Video
        do {
            write-host "We're in the loop"
            if($i -eq $partcount)
            {
                $FFMPEGCommand = $FFMPEGCommand + "[0]atrim=" + $cursor + ":" + ($cursor + $IncLength + $LastPartInc) +",asetpts=PTS-STARTPTS[ap"+ ($i + 2) +"],[0]trim="+ $cursor + ":" + ($cursor + $IncLength + $LastPartInc) + ",setpts=PTS-STARTPTS[p" + ($i + 2) + "],"
            }
            else 
            {
                $FFMPEGCommand = $FFMPEGCommand + "[0]atrim=" + $cursor + ":" + ($cursor + $IncLength) +",asetpts=PTS-STARTPTS[ap"+ ($i + 2) +"],[0]trim="+ $cursor + ":" + ($cursor + $IncLength) + ",setpts=PTS-STARTPTS[p" + ($i + 2) + "],"
            }
            
            
            $cursor = $Cursor + $IncDist
            $CommandMid = $CommandMid + "[p" + ($i + 2) + "][ap" + ($i + 2) + "]"   
            $i++
        } while ($i -ne $partcount)
        $lpart = $Partcount + 2
        $FFMPEGCommand = $ffmpegCommand + "[0]atrim=" + $LandingBegin + ":" + $LandingEnd + ",asetpts=PTS-STARTPTS[ap" + $lpart +"],[0]trim=" + $LandingBegin + ":" + $LandingEnd + ",setpts=PTS-STARTPTS[p"+ $lpart + "]," + $CommandMid + "[p" + $lpart + "][ap" + $lpart + "]" 
        $FFMPEGCommand = $FFMPEGCommand + "concat=n="+ $lpart + ":v=1:a=1[out][aout]" + [char]34 + " -map " + [char]34 + "[out]" + [char]34 + " -map " + [char]34 + "[aout]" + [char]34 + " " + $OutputPath + " -hwaccel cuda -hwaccel_output_format cuda -y"
    }
    
    end 
    {
        #Run Command
        write-host $ffmpegCommand
        start-process -FilePath $ffmpegPath -ArgumentList $FFMPEGCommand -PassThru -wait -nonewWindow
    }
}


create-summary -ffmpegPath "C:\git\PS_VidAggregator\ffmpeg\ffmpeg.exe" -VideoPath "Z:\alf\ParaglidingVids\2022-10-07-LongFlight.mp4" -OutputPath "D:\Insta360Parts\20221007-Summary.mp4" -LaunchBegin 0 -LaunchEnd 15 -LandingBegin 3635 -LandingEnd 3645 -IncLength 10 -VideoLength 321

#create-summary -ffmpegPath "C:\git\PS_VidAggregator\ffmpeg\ffmpeg.exe" -VideoPath "D:\Insta360Parts\20221016-Full.mp4" -OutputPath "D:\Insta360Parts\20221016-Summary.mp4" -LaunchBegin 0 -LaunchEnd 12 -LandingBegin 3470 -LandingEnd 3485 -IncLength 10 -VideoLength 270