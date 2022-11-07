. ($PSScriptRoot + "\lib.ps1")
$ffmpegPath = $PSScriptRoot + "\ffmpeg\ffmpeg.exe"

function new-Summary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage="Path to FFMPEG.exe",ValueFromPipeline=$true)][string]$ffmpegPath,
        [Parameter(Mandatory=$true,HelpMessage="Path to input Video",ValueFromPipeline=$true)][string]$VideoPath,
        [Parameter(Mandatory=$true,HelpMessage="Path to where the Output should end",ValueFromPipeline=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true,HelpMessage="Value in Seconds on how Long the Resulting Video should be",ValueFromPipeline=$true)][int]$SummaryLength,
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

        #get the Begin and End of Video and Calculate Input Video used Length
        $VideoBegin = ($InputParts.Start | sort-object)[0]
        $VideoEnding = ($InputParts.End | sort-object -Descending)[0]
        $InputLength = $VideoEnding - $VideoBegin
        write-host ("Input Video usable length is: " + $InputLength)

        #Create a Counter to keep Track of Summary Length beeing built. 
        $OV_cur_len = 0
        #Add the Input Parts to the Counter
        foreach($entry in $InputParts)
        {
            $OV_cur_len = $OV_cur_len + ($entry.end - $entry.start)
        }
        #Calculate Seconds left in Summary after InputParts
        $OV_var_Part_len = $SummaryLength - $OV_cur_len
        #Calculate amounth of Parts needed to be generated
        [int]$varParts = ($OV_var_Part_len / $IncLength)
        #Calculate the Distance between parts
        [int]$IncDist =  $OV_var_Part_len / $varParts
        #Give Myself an overview
        write-host ("Input Parts have been " + $OV_cur_len + " Seconds Long which leaves only " + $OV_var_Part_len + " Seconds of the " + $SummaryLength + " Seconds Total SummaryTime and will result in " + $varParts + " Parts generated Automatically! Increment distance is: " + $IncDist)

        #Add Input Parts to Parts
        $parts = $InputParts
    }
    
    process 
    {
        #Create Cursor
        $vidCursor = $VideoBegin
        #Generate Variable Parts and add them to Parts
        do {
            $vidCursor = $VidCursor + $IncDist
            $newpart = @{Start=$vidCursor;End=($vidCursor + $IncLength)}
            
            $start = $true
            $end = $true

            for ($i = -30; $i -lt 30; $i++) 
            {
                if($parts.start -contains ($newpart.start + $i))
                {
                    $start = $false
                }

                if($parts.end -contains ($newpart.end + $i))
                {
                    $end = $false
                }
            }

            if($start -eq $true -and $end -eq $true)
            {
                $OV_cur_len = $OV_cur_len + ($newpart.end - $newpart.start)
                if($OV_cur_len -gt ($SummaryLength - $incLength))
                {
                    $diff = $SummaryLength - $OV_cur_len
                    $newpart.end = $newpart.end + $diff
                    $parts += $newpart
                    $OV_cur_len = $OV_cur_len + $diff
                    return
                }
                else 
                {
                    $parts += $newpart
                }
                
            }

            
        } until (
            $OV_cur_len -eq $SummaryLength
        )

        #Prepare first Part of Command with Launch
        $FFMPEGCommand = "-i $VideoPath -filter_complex " + [char]34
        foreach($part in $parts)
        {
            $FFMPEGCommand = $FFMPEGCommand + "[0]atrim=" + $part.start + ":" + $part.end + ",asetpts=PTS-STARTPTS[ap" + $parts.IndexOf($part) +"],[0]trim=" + $part.start + ":" + $part.end + ",setpts=PTS-STARTPTS[p" + $parts.IndexOf($part) +"],"
            $FFMPEGMid = $FFMPEGMid + "[p" + $parts.IndexOf($part) +"]" + "[ap" + $parts.IndexOf($part) +"]"
        }

        #Stitch the Commands
        $FFMPEGCommand = $FFMPEGCommand + $FFMPEGMid + "concat=n="+ $parts.count + ":v=1:a=1[out][aout]" + [char]34 + " -map " + [char]34 + "[out]" + [char]34 + " -map " + [char]34 + "[aout]" + [char]34 + " " + $OutputPath + " -hwaccel cuda -hwaccel_output_format cuda -y"
        
    }
    
    end 
    {
        #Run Command
        write-host $ffmpegCommand
        #start-process -FilePath $ffmpegPath -ArgumentList $FFMPEGCommand -PassThru -wait -nonewWindow
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

$global:VideoInput = "test"
$global:VideoOutput = "test"

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
            $global:VideoInput = $of_VDSelect.FileName
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
create-label "Length of Video Parts" 5 $fm_cursor $fm_sum | Out-Null
create-Timepick "IncLength" "00:00:10" 150 ($fm_cursor-2) $fm_sum

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
            $global:VideoOutput = $of_VDOut.FileName
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

        $LaunchBegin = [int]([timespan]($fm_sum.Controls | where-object {$_.Name -like "LaunchBegin"}).text).TotalSeconds
        write-host ("Launchbegin " + $LaunchBegin)
        $LaunchEnd = [int]([timespan]($fm_sum.Controls | where-object {$_.Name -like "LaunchEnd"}).text).TotalSeconds
        write-host ("LaunchEnd " + $LaunchEnd)
        $LandingBegin = [int]([timespan]($fm_sum.Controls | where-object {$_.Name -like "LandingBegin"}).text).TotalSeconds
        write-host ("Landing Begin " + $LandingBegin)
        $LandingEnd = [int]([timespan]($fm_sum.Controls | where-object {$_.Name -like "LandingEnd"}).text).TotalSeconds
        write-host ("Landing End " + $LandingEnd)
        $SummaryLength = [int]([timespan]($fm_sum.Controls | where-object {$_.Name -like "SummaryLength"}).text).TotalSeconds
        write-host ("Summary Length " + $SummaryLength)
        $IncLength = [int]([timespan]($fm_sum.Controls | where-object {$_.Name -like "IncLength"}).text).TotalSeconds
        write-host ("IncLength " + $IncLength)
        write-host ("this is the Input Video " + $VideoInput)
        write-host ("this is the Output Video" + $VideoOutput)

        #Todo: Get Inputs from Form and trigger Summary Creation
        $InputParts = @(@{Start=$LaunchBegin;End=$LaunchEnd},@{Start=$LandingBegin;End=$LandingEnd})
        
        new-summary -ffmpegPath $ffmpegpath -VideoPath $VideoInput -OutputPath $VideoOutput -IncLength $IncLength -SummaryLength $SummaryLength -InputParts $inputParts

    }
)
#Show Form
$fm_sum.ShowDialog()