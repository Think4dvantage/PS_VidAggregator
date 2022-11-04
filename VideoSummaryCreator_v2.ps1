. ($PSScriptRoot + "\lib.ps1")

function new-Summary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage="Path to FFMPEG.exe",ValueFromPipeline=$true)][string]$ffmpegPath,
        [Parameter(Mandatory=$true,HelpMessage="Path to input Video",ValueFromPipeline=$true)][string]$VideoPath,
        [Parameter(Mandatory=$true,HelpMessage="Path to where the Output should end",ValueFromPipeline=$true)][string]$OutputPath,
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

#Forms
Add-Type -assembly System.Windows.Forms
$fm_sum = New-Object System.Windows.Forms.Form

$fm_sum.Text ='Video Summary'
$fm_sum.AutoSize = $true
$fm_sum.Width = 500
$fm_sum.Height = 720
$fm_sum.AutoScroll = $true

$fm_cursor = 5

create-label "Video selected:" 5 $fm_cursor $fm_sum | Out-Null
$lb_VDPath = create-label " " 100 $fm_cursor $fm_sum 
$btn_VDSelect = create-button "Select Video" 80 23 400 ($fm_cursor -2) $fm_sum
$btn_VDSelect.add_click( 
    { 
        $of_VDSelect = New-Object System.Windows.Forms.OpenFileDialog
        $of_VDSelect.InitialDirectory = "D:\"
        $of_VDSelect.Title = "Please Select a Video File"
        $of_VDSelect.filter = "Videodateien (*.mp4)|*.mp4"
        if($of_VDSelect.ShowDialog() -eq "Ok")
        {
            $lb_VDPath.Text = $of_VDSelect.FileName
            $fm_sum.Refresh()
        }
        else {
            $fm_sum.close()
        }
    }
)
$fm_cursor = $fm_cursor + 25
create-label "Launch Begin:" 5 $fm_cursor $fm_sum | Out-Null
create-Timepick "LaunchBegin" "00:00:00" 150 ($fm_cursor-2) $fm_sum

$fm_cursor = $fm_cursor + 25
create-label "Launch End:" 5 $fm_cursor $fm_sum | Out-Null
create-Timepick "LaunchEnd" "00:00:15" 150 ($fm_cursor-2) $fm_sum

$fm_cursor = $fm_cursor + 25
create-label "Landing Begin:" 5 $fm_cursor $fm_sum | Out-Null
create-Timepick "LandingBegin" "00:08:00" 150 ($fm_cursor-2) $fm_sum

$fm_cursor = $fm_cursor + 25
create-label "Landing End:" 5 $fm_cursor $fm_sum | Out-Null
create-Timepick "LandingEnd" "00:08:10" 150 ($fm_cursor-2) $fm_sum

$fm_cursor = $fm_cursor + 25
create-label "Expected Summary Length:" 5 $fm_cursor $fm_sum | Out-Null
create-Timepick "SummaryLength" "00:05:00" 150 ($fm_cursor-2) $fm_sum

$fm_cursor = $fm_cursor + 25
create-label "Output Path:" 5 $fm_cursor $fm_sum | Out-Null
$lb_VDOut = create-label " " 100 $fm_cursor $fm_sum 
$btn_VDOut = create-button "Output Path" 80 23 400 ($fm_cursor -2) $fm_sum
$btn_VDOut.add_click( 
    { 
        $of_VDOut = New-Object System.Windows.Forms.SaveFileDialog
        $of_VDOut.InitialDirectory = $of_VDSelect.FileName
        $of_VDOut.Title = "Please Select Output File"
        $of_VDOut.filter = "Videodateien (*.mp4)|*.mp4"
        if($of_VDOut.ShowDialog() -eq "Ok")
        {
            $lb_VDOut.Text = $of_VDOut.FileName
            $fm_sum.Refresh()
        }
        else {
            write-host "no file Selected"
        }
    }
)

$fm_cursor = $fm_cursor + 25
$btn_VDRun = create-button "Create Summary" 80 23 400 ($fm_cursor -2) $fm_sum
$btn_VDRun.add_Click(
    {
        write-host "Running Summary Script"

        $LaunchBegin = ($fm_sum.Controls | where-object {$_.Name -like "LaunchBegin"}).Text
        $LaunchEnd = ($fm_sum.Controls | where-object {$_.Name -like "LaunchEnd"}).Text
        $LandingBegin = ($fm_sum.Controls | where-object {$_.Name -like "LandingBegin"}).Text
        $LandingEnd = ($fm_sum.Controls | where-object {$_.Name -like "LandingEnd"}).Text

        #Todo: Get Inputs from Form and trigger Summary Creation
        $InputParts = @(@{Start=0;End=15},@{Start=3640;End=3650})
        
        #new-summary -ffmpegPath "C:\git\PS_VidAggregator\ffmpeg\ffmpeg.exe" -VideoPath "Z:\alf\ParaglidingVids\2022-10-07-LongFlight.mp4" -OutputPath "D:\Insta360Parts\20221007-Summary.mp4" -IncLength 10 -VideoLength 321 -InputParts $inputParts

    }
)
#Show Form
$fm_sum.ShowDialog()

#Creating Array with Input of Launch Start and Landing Start



#create-summary -ffmpegPath "C:\git\PS_VidAggregator\ffmpeg\ffmpeg.exe" -VideoPath "D:\Insta360Parts\20221016-Full.mp4" -OutputPath "D:\Insta360Parts\20221016-Summary.mp4" -LaunchBegin 0 -LaunchEnd 12 -LandingBegin 3470 -LandingEnd 3485 -IncLength 10 -VideoLength 270