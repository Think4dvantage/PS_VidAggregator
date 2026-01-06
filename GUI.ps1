#Getting GUI Lib
. .\lib.ps1
#Getting VideoSummary Creator 
. .\VideoSummaryCreator

#File Selector with multi-file support
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
$FileBrowser.InitialDirectory = "D:\"
$FileBrowser.Filter = "mp4 files (*.mp4)|*.mp4|All files (*.*)|*.*"
$FileBrowser.Multiselect = $true
$null = $FileBrowser.ShowDialog()

# Check if multiple files selected
if ($FileBrowser.FileNames.Count -gt 1) {
    $result = [System.Windows.Forms.MessageBox]::Show(
        "You selected $($FileBrowser.FileNames.Count) files. Do you want to concatenate them?",
        "Multiple Files Selected", 
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Generate output filename by removing number suffix from first file
        $firstFile = $FileBrowser.FileNames[0]
        $directory = [System.IO.Path]::GetDirectoryName($firstFile)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($firstFile)
        
        # Remove trailing numbers (e.g., "Date_FullFlight1" -> "Date_FullFlight")
        $baseName = $baseName -replace '\d+$', ''
        $outputFile = Join-Path $directory ($baseName + ".mp4")
        
        # Source the concatenation function
        . "$PSScriptRoot\VideoConcatenator.ps1"
        
        Write-Host "Concatenating files to: $outputFile"
        Concatenate-Video -VideoParts $FileBrowser.FileNames -deleteParts $false -Output $outputFile
        
        # Ask user to verify
        $verifyResult = [System.Windows.Forms.MessageBox]::Show(
            "Concatenation complete: $outputFile`n`nPlease check if the video is correct. Do you want to delete the original files?",
            "Verify Concatenated Video",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        if ($verifyResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            # Delete original files
            foreach ($file in $FileBrowser.FileNames) {
                Remove-Item -Path $file -Force
                Write-Host "Deleted: $file"
            }
            Write-Host "Original files deleted. Using concatenated file: $outputFile"
        }
        
        # Set VideoFile to the concatenated output
        $VideoFile = $outputFile
    } else {
        # User declined concatenation, ask to select one file
        [System.Windows.Forms.MessageBox]::Show(
            "Please select only one file to process.",
            "Select Single File",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        exit
    }
} else {
    # Single file selected
    $VideoFile = $FileBrowser.FileName
}

# Validate file selection
if([string]::IsNullOrWhiteSpace($VideoFile) -or !(Test-Path $VideoFile)) {
    [System.Windows.Forms.MessageBox]::Show("No valid video file selected. Exiting.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

#Setup Archive Directory
$Global:archiveDir = Join-Path $PSScriptRoot "archive"
if(!(Test-Path $Global:archiveDir)) {
    New-Item -ItemType Directory -Path $Global:archiveDir | Out-Null
}

#Get Video Identifier (filename without extension)
$Global:videoIdentifier = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile)
$Global:archiveFile = Join-Path $Global:archiveDir "$Global:videoIdentifier.json"
$Global:isLoading = $false

# Debounce timer for save operations
$Global:saveTimer = New-Object System.Windows.Forms.Timer
$Global:saveTimer.Interval = 2000  # 2 seconds
$Global:saveTimer.Add_Tick({
    $Global:saveTimer.Stop()
    Save-GUIDataImmediate
})

#Save Function (debounced)
function Save-GUIData {
    if($Global:isLoading) {
        write-host "Skipping save during loading"
        return
    }
    
    # Reset the timer - this delays the save
    $Global:saveTimer.Stop()
    $Global:saveTimer.Start()
}

#Immediate Save Function (no debounce)
function Save-GUIDataImmediate {
    if($Global:isLoading) {
        write-host "Skipping save during loading"
        return
    }
    
    try {
        $data = @{
            SummaryLength = $TPSummaryLength.Text
            SummaryName = $TBSummaryName.Text
            Highlights = @()
        }
    
        $highlightGroupBoxes = ($SummaryGUI.Controls | where-object {$_.Name -eq ("GPHighlights")}).Controls | where-object {$_.Name -eq ("HIGHLIGHTElement")}
        foreach($highlightBox in $highlightGroupBoxes) {
            $startControl = $highlightBox.Controls | where-object {$_.Name -like "TPStart"}
            $endControl = $highlightBox.Controls | where-object {$_.Name -like "TPEnd"}
            $commentControl = $highlightBox.Controls | where-object {$_.Name -like "TBComment"}
        
            if($startControl -and $endControl) {
                $data.Highlights += @{
                    Start = $startControl.Text
                    End = $endControl.Text
                    Comment = if($commentControl) { $commentControl.Text } else { "" }
                }
            }
        }
    
        $data | ConvertTo-Json -Depth 10 | Set-Content -Path $Global:archiveFile -Encoding UTF8
        write-host "Data saved to $Global:archiveFile"
    }
    catch {
        write-host "Error saving data: $($_.Exception.Message)" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show("Failed to save data: $($_.Exception.Message)", "Save Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}

#Load Function
function Load-GUIData {
    try {
        if(Test-Path $Global:archiveFile) {
            $Global:isLoading = $true
            write-host "Loading data from $Global:archiveFile"
            $data = Get-Content -Path $Global:archiveFile -Raw | ConvertFrom-Json
        
            # Load Summary Length and Name
            if($data.SummaryLength) {
                $TPSummaryLength.Text = $data.SummaryLength
            }
            if($data.SummaryName) {
                $TBSummaryName.Text = $data.SummaryName
            }
        
            # Load Highlights
            if($data.Highlights -and $data.Highlights.Count -gt 0) {
                foreach($highlight in $data.Highlights) {
                    write-host "Loading highlight: Start=$($highlight.Start), End=$($highlight.End), Comment=$($highlight.Comment)"
                    
                    # Manually create highlight groupbox (don't use PerformClick to avoid side effects)
                    $Highlights.Height = $Highlights.Height + 78
                    $RandoHighlight = create-GroupBox -Name "HIGHLIGHTElement" -Height 75 -width 950 -fromLeft 5 -fromTop $Global:highFromTop -addTo $Highlights
                    create-Label -Text "Start" -fromLeft 5 -fromTop 10 -AddTo $RandoHighlight
                    create-Timepick -Name "TPStart" -fromLeft 75 -fromTop 10 -AddTo $RandoHighlight -Text $highlight.Start
                    create-Label -Text "End" -fromLeft 200 -fromTop 10 -AddTo $RandoHighlight
                    create-Timepick -Name "TPEnd" -fromLeft 275 -fromTop 10 -AddTo $RandoHighlight -Text $highlight.End
                    create-Label -Text "Comment" -fromLeft 5 -fromTop 40 -AddTo $RandoHighlight
                    
                    $TBCommentLoad = New-Object System.Windows.Forms.TextBox
                    $TBCommentLoad.Name = "TBComment"
                    $TBCommentLoad.width = 300
                    $TBCommentLoad.MaxLength = 200
                    $TBCommentLoad.Text = $highlight.Comment
                    $TBCommentLoad.Location = New-Object System.Drawing.Point(75,40)
                    $TBCommentLoad.Add_LostFocus({ Save-GUIData })
                    $RandoHighlight.Controls.Add($TBCommentLoad)
                    
                    # Add Delete Button
                    $BTDelete = create-Button -text "X" -width 30 -height 30 -fromleft 900 -fromTop 20 -addTo $RandoHighlight
                    $BTDelete.BackColor = [System.Drawing.Color]::IndianRed
                    $BTDelete.Add_Click({
                        # Remove this highlight groupbox
                        $highlightToRemove = $this.Parent
                        $Highlights.Controls.Remove($highlightToRemove)
                        
                        # Recalculate positions and heights
                        $remainingHighlights = ($Highlights.Controls | where-object {$_.Name -eq "HIGHLIGHTElement"})
                        $newTop = 15
                        foreach($hl in $remainingHighlights) {
                            $hl.Location = New-Object System.Drawing.Point(5, $newTop)
                            $newTop += 78
                        }
                        
                        # Update container height and global offset
                        $Highlights.Height = 25 + ($remainingHighlights.Count * 78)
                        $Global:highFromTop = $newTop
                        
                        # Update display and save
                        $SummaryGUI.Update()
                        Update-HighlightsTotal
                        Save-GUIDataImmediate
                    })
                    
                    # Add LostFocus to time pickers
                    $tpStart = ($RandoHighlight.Controls | where-object {$_.Name -like "TPStart"})
                    $tpEnd = ($RandoHighlight.Controls | where-object {$_.Name -like "TPEnd"})
                    
                    # Auto-fill End time when Start is modified
                    $tpStart.Add_LostFocus({
                        $parentBox = $this.Parent
                        $startCtrl = $this
                        $endCtrl = $parentBox.Controls | where-object {$_.Name -like "TPEnd"}
                        if($endCtrl) {
                            $endCtrl.Value = $startCtrl.Value.AddSeconds(5)
                        }
                        Save-GUIData
                        Update-HighlightsTotal
                    })
                    
                    $tpEnd.Add_LostFocus({ Save-GUIData; Update-HighlightsTotal })
                    
                    $Global:highFromTop += 78
                }
                $SummaryGUI.Update()
            }
        
            $Global:isLoading = $false
            Update-HighlightsTotal
            write-host "Data loaded successfully"
        }
        else {
            $Global:isLoading = $false
            write-host "No saved data found for this video"
        }
    }
    catch {
        $Global:isLoading = $false
        write-host "Error loading data: $($_.Exception.Message)" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show("Failed to load saved data: $($_.Exception.Message)", "Load Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}

#Calculate Highlights Total Function
function Update-HighlightsTotal {
    $totalSeconds = 0
    $highlightGroupBoxes = ($SummaryGUI.Controls | where-object {$_.Name -eq ("GPHighlights")}).Controls | where-object {$_.Name -eq ("HIGHLIGHTElement")}
    
    foreach($highlightBox in $highlightGroupBoxes) {
        $startControl = $highlightBox.Controls | where-object {$_.Name -like "TPStart"}
        $endControl = $highlightBox.Controls | where-object {$_.Name -like "TPEnd"}
        
        if($startControl -and $endControl) {
            $startTime = $startControl.Value
            $endTime = $endControl.Value
            
            $start = [int]($startTime.Hour * 3600 + $startTime.Minute * 60 + $startTime.Second)
            $end = [int]($endTime.Hour * 3600 + $endTime.Minute * 60 + $endTime.Second)
            
            if($end -gt $start) {
                $totalSeconds += ($end - $start)
            }
        }
    }
    
    $LBHighlightsTotal.Text = "$totalSeconds seconds"
    
    # Check if highlights exceed 70% of summary length and adjust if needed
    $currentSummaryTime = $TPSummaryLength.Value
    $currentSummarySeconds = [int]($currentSummaryTime.Hour * 3600 + $currentSummaryTime.Minute * 60 + $currentSummaryTime.Second)
    
    $maxHighlightsAllowed = $currentSummarySeconds * 0.7
    
    if($totalSeconds -gt $maxHighlightsAllowed) {
        # Calculate new minimum summary length (highlights / 0.7)
        $newSummarySeconds = [math]::Ceiling($totalSeconds / 0.7)
        
        # Convert seconds to hours, minutes, seconds
        $hours = [math]::Floor($newSummarySeconds / 3600)
        $minutes = [math]::Floor(($newSummarySeconds % 3600) / 60)
        $seconds = $newSummarySeconds % 60
        
        # Update the time picker
        $TPSummaryLength.Value = (Get-Date).Date.AddHours($hours).AddMinutes($minutes).AddSeconds($seconds)
        
        write-host "Summary length auto-adjusted to $newSummarySeconds seconds to maintain 70% highlights limit"
    }
}

#Create Form 
$SummaryGUI = New-Object System.Windows.Forms.Form
$SummaryGUI.Text ='Video Summary Creator'
$SummaryGUI.AutoSize = $false
$SummaryGUI.Width = 1200
$SummaryGUI.Height = 700
$SummaryGUI.AutoScroll = $true

#Create Title Label 
create-Label -Text ($VideoFile.Split("\"))[-1] -fromLeft 10 -fromTop 10 -AddTo $SummaryGUI -Type "Title"

#Add Summary Length Field
create-Label -Text "Summary Length" -fromLeft 10 -fromTop 50 -AddTo $SummaryGUI
$TPSummaryLength = New-Object System.Windows.Forms.DateTimePicker
$TPSummaryLength.Name = "TPSummaryLength"
$TPSummaryLength.Format = [windows.forms.datetimepickerFormat]::time
$TPSummaryLength.ShowUpDown = $true
$TPSummaryLength.Size = New-Object System.Drawing.Size(120,23)
$TPSummaryLength.Value = (Get-Date).Date.AddMinutes(1).AddSeconds(30)
$TPSummaryLength.Location = New-Object System.Drawing.Point(150,50)
$TPSummaryLength.Add_LostFocus({ Save-GUIData })
$SummaryGUI.Controls.Add($TPSummaryLength)

#Add Summary Name Field
create-Label -Text "Summary Name" -fromLeft 10 -fromTop 80 -AddTo $SummaryGUI
$TBSummaryName = New-Object System.Windows.Forms.TextBox
$TBSummaryName.Name = "TBSummaryName"
$TBSummaryName.Width = 300
$TBSummaryName.MaxLength = 200
$fileName = ($VideoFile.Split("\\"))[-1].Replace(".mp4","")
if($fileName -match "(.+)_")
{
    $TBSummaryName.Text = $matches[1] + "_Summary"
}
else
{
    $TBSummaryName.Text = $fileName + "_Summary"
}
$TBSummaryName.Location = New-Object System.Drawing.Point(150,80)
$TBSummaryName.Add_LostFocus({ Save-GUIData })
$SummaryGUI.Controls.Add($TBSummaryName)

#Add Highlights Total Field
create-Label -Text "Highlights Total" -fromLeft 300 -fromTop 50 -AddTo $SummaryGUI
$LBHighlightsTotal = New-Object System.Windows.Forms.Label
$LBHighlightsTotal.Text = "0 seconds"
$LBHighlightsTotal.AutoSize = $true
$LBHighlightsTotal.Location = New-Object System.Drawing.Point(420,50)
$LBHighlightsTotal.Font = New-Object System.Drawing.Font("Arial",10,[System.Drawing.FontStyle]::Bold)
$SummaryGUI.Controls.Add($LBHighlightsTotal)

#Add Highligts GroupBox
$Highlights = create-GroupBox -Name "GPHighlights" -Height 25 -width 1000 -fromLeft 5 -fromTop 120 -addTo $SummaryGUI

#PlusButton
$BTAddHighlight = create-Button -text "+" -width 70 -height 25 -fromleft 1015 -fromTop 130 -addTo $SummaryGUI

#Prepare Offset from Top for Add Function
$Global:highFromTop = 15

#Add Highlight Input Function
$BTAddHighlight.Add_Click(
    {
        write-host "HighlightAdd Button has been clicked"
        $Highlights.Height = $Highlights.Height + 78
        $RandoHighlight = create-GroupBox -Name "HIGHLIGHTElement" -Height 75 -width 950 -fromLeft 5 -fromTop $highFromTop -addTo $Highlights
        create-Label -Text "Start" -fromLeft 5 -fromTop 10 -AddTo $RandoHighlight
        create-Timepick -Name "TPStart" -fromLeft 75 -fromTop 10 -AddTo  $RandoHighlight -Text "00:00:00"
        create-Label -Text "End" -fromLeft 200 -fromTop 10 -AddTo $RandoHighlight
        create-Timepick -Name "TPEnd" -fromLeft 275 -fromTop 10 -AddTo  $RandoHighlight -Text "00:00:00"
        create-Label -Text "Comment" -fromLeft 5 -fromTop 40 -AddTo $RandoHighlight
        $TBCommentNew = New-Object System.Windows.Forms.TextBox
        $TBCommentNew.Name = "TBComment"
        $TBCommentNew.width = 300
        $TBCommentNew.MaxLength = 200
        $TBCommentNew.Location = New-Object System.Drawing.Point(75,40)
        $TBCommentNew.Add_LostFocus({ Save-GUIData })
        $RandoHighlight.Controls.Add($TBCommentNew)
        
        # Add Delete Button
        $BTDelete = create-Button -text "X" -width 30 -height 30 -fromleft 900 -fromTop 20 -addTo $RandoHighlight
        $BTDelete.BackColor = [System.Drawing.Color]::IndianRed
        $BTDelete.Add_Click({
            # Remove this highlight groupbox
            $highlightToRemove = $this.Parent
            $Highlights.Controls.Remove($highlightToRemove)
            
            # Recalculate positions and heights
            $remainingHighlights = ($Highlights.Controls | where-object {$_.Name -eq "HIGHLIGHTElement"})
            $newTop = 15
            foreach($hl in $remainingHighlights) {
                $hl.Location = New-Object System.Drawing.Point(5, $newTop)
                $newTop += 78
            }
            
            # Update container height and global offset
            $Highlights.Height = 25 + ($remainingHighlights.Count * 78)
            $Global:highFromTop = $newTop
            
            # Update display and save
            $SummaryGUI.Update()
            Update-HighlightsTotal
            Save-GUIDataImmediate
        })
        
        # Add LostFocus to time pickers
        $tpStart = ($RandoHighlight.Controls | where-object {$_.Name -like "TPStart"})
        $tpEnd = ($RandoHighlight.Controls | where-object {$_.Name -like "TPEnd"})
        
        # Auto-fill End time when Start is modified
        $tpStart.Add_LostFocus({
            $parentBox = $this.Parent
            $startCtrl = $this
            $endCtrl = $parentBox.Controls | where-object {$_.Name -like "TPEnd"}
            if($endCtrl) {
                $endCtrl.Value = $startCtrl.Value.AddSeconds(5)
            }
            Save-GUIData
            Update-HighlightsTotal
        })
        
        $tpEnd.Add_LostFocus({ Save-GUIData; Update-HighlightsTotal })
        
        $Global:highFromTop += 78
        $SummaryGUI.Update()
        Update-HighlightsTotal
    }
)

#Add RUN Button 
$BTNrun = create-Button -text "RUN" -width 100 -height 25 -fromleft 1015 -fromTop 5 -addTo $SummaryGUI

#Add RUN Function
$BTNrun.Add_Click(
    {
        try {
            write-host "RUN Button has been clicked"
            $manualHighlights = @()
            $highlightGroupBoxes = ($SummaryGUI.Controls | where-object {$_.Name -eq ("GPHighlights")}).Controls | where-object {$_.Name -eq ("HIGHLIGHTElement")}
        
            if($highlightGroupBoxes.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No highlights added. Please add at least one highlight.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
        
            foreach($highlightBox in $highlightGroupBoxes)
            {
                write-host "Processing highlight groupbox..."
                $StartTime = ($highlightBox.Controls | where-object {$_.Name -like "TPStart"}).Value
                $EndTime = ($highlightBox.Controls | where-object {$_.Name -like "TPEnd"}).Value
                $Comment = ($highlightBox.Controls | where-object {$_.Name -like "TBComment"}).Text
            
                # Convert time to seconds
                $Start = [int]($StartTime.Hour * 3600 + $StartTime.Minute * 60 + $StartTime.Second)
                $End = [int]($EndTime.Hour * 3600 + $EndTime.Minute * 60 + $EndTime.Second)
            
                # Validate time range
                if($End -le $Start) {
                    [System.Windows.Forms.MessageBox]::Show("Invalid highlight: End time must be after Start time.`nStart: $Start seconds, End: $End seconds", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
            
                write-host "Start: $Start seconds, End: $End seconds, Comment: $Comment"
                $manualHighlights += [PSCustomObject]@{start=$Start; end=$End; comment=$Comment}
            }
            write-host "`nAll highlights collected:"
            write-host ($manualHighlights | Format-Table | Out-String)
        
            # Collect Summary Length and Summary Name
            $SummaryLengthTime = $TPSummaryLength.Value
            $SummaryLength = [int]($SummaryLengthTime.Hour * 3600 + $SummaryLengthTime.Minute * 60 + $SummaryLengthTime.Second)
            $SummaryNameOnly = $TBSummaryName.Text
            $VideoDirectory = Split-Path $VideoFile -Parent
            $SummaryName = Join-Path $VideoDirectory ($SummaryNameOnly + ".mp4")
        
            write-host "`nSummary Length: $SummaryLength seconds"
            write-host "Summary Name: $SummaryName"

            # Call aggregate-Video function with collected data
            write-host "`nStarting video processing..."
            $result = aggregate-Video -SourceVideoPath $VideoFile -Highlights $manualHighlights -OutputLength $SummaryLength -PartLength 4 -OutputPath $SummaryName
            
            if($result -eq $false) {
                [System.Windows.Forms.MessageBox]::Show("Video processing failed. Check console for details.", "Processing Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
            else {
                [System.Windows.Forms.MessageBox]::Show("Video summary created successfully!`n`nOutput: $SummaryName", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        }
        catch {
            write-host "Error during video processing: $($_.Exception.Message)" -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show("An error occurred during video processing:`n`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
)

# Load existing data if available
Load-GUIData

$SummaryGUI.ShowDialog()