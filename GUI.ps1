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
            $pictureControl = $highlightBox.Controls | where-object {$_.Name -like "CBPicture"}
            $imagePathControl = $highlightBox.Controls | where-object {$_.Name -like "TBImagePath"}
            $durationControl = $highlightBox.Controls | where-object {$_.Name -like "NBDuration"}
        
            if($startControl -and $endControl) {
                $highlightData = @{
                    Start = $startControl.Text
                    End = $endControl.Text
                    Comment = if($commentControl) { $commentControl.Text } else { "" }
                    Type = if($pictureControl -and $pictureControl.Checked) { "picture" } else { "video" }
                }
                
                # Add picture-specific fields if picture mode
                if($pictureControl -and $pictureControl.Checked) {
                    $highlightData.ImagePath = if($imagePathControl) { $imagePathControl.Text } else { "" }
                    $highlightData.Duration = if($durationControl) { [int]$durationControl.Value } else { 5 }
                }
                
                $data.Highlights += $highlightData
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
                    write-host "Loading highlight: Start=$($highlight.Start), End=$($highlight.End), Comment=$($highlight.Comment), Type=$($highlight.Type)"
                    
                    # Manually create highlight groupbox (don't use PerformClick to avoid side effects)
                    $Highlights.Height = $Highlights.Height + 78
                    $RandoHighlight = create-GroupBox -Name "HIGHLIGHTElement" -Height 75 -width 950 -fromLeft 5 -fromTop $Global:highFromTop -addTo $Highlights
                    
                    # Start Label (changes meaning based on Picture checkbox)
                    $LBStart = New-Object System.Windows.Forms.Label
                    $LBStart.Name = "LBStart"
                    $LBStart.Text = if($isPicture) { "Insert At" } else { "Start" }
                    $LBStart.AutoSize = $true
                    $LBStart.Location = New-Object System.Drawing.Point(5,10)
                    $RandoHighlight.Controls.Add($LBStart)
                    
                    create-Timepick -Name "TPStart" -fromLeft 75 -fromTop 10 -AddTo $RandoHighlight -Text $highlight.Start
                    create-Label -Text "End" -fromLeft 200 -fromTop 10 -AddTo $RandoHighlight
                    create-Timepick -Name "TPEnd" -fromLeft 275 -fromTop 10 -AddTo $RandoHighlight -Text $highlight.End
                    
                    # Picture Highlight Controls
                    $isPicture = ($highlight.Type -eq "picture")
                    $CBPicture = New-Object System.Windows.Forms.CheckBox
                    $CBPicture.Name = "CBPicture"
                    $CBPicture.Text = "Picture"
                    $CBPicture.Width = 80
                    $CBPicture.Height = 20
                    $CBPicture.Checked = $isPicture
                    $CBPicture.Location = New-Object System.Drawing.Point(410,10)
                    $CBPicture.Add_CheckedChanged({
                        $parent = $this.Parent
                        $isPic = $this.Checked
                        # Update label text based on mode
                        $startLabel = $parent.Controls | where-object {$_.Name -eq "LBStart"}
                        if($startLabel) {
                            $startLabel.Text = if($isPic) { "Insert At" } else { "Start" }
                        }
                        # Keep Start enabled for timeline position, disable only End time
                        ($parent.Controls | where-object {$_.Name -eq "TPEnd"}).Enabled = !$isPic
                        ($parent.Controls | where-object {$_.Name -eq "BTBrowse"}).Visible = $isPic
                        ($parent.Controls | where-object {$_.Name -eq "TBImagePath"}).Visible = $isPic
                        ($parent.Controls | where-object {$_.Name -eq "LBDuration"}).Visible = $isPic
                        ($parent.Controls | where-object {$_.Name -eq "NBDuration"}).Visible = $isPic
                        Save-GUIData
                    })
                    $RandoHighlight.Controls.Add($CBPicture)
                    
                    # Image Path
                    $TBImagePath = New-Object System.Windows.Forms.TextBox
                    $TBImagePath.Name = "TBImagePath"
                    $TBImagePath.Width = 200
                    $TBImagePath.ReadOnly = $true
                    if($highlight.ImagePath) {
                        $TBImagePath.Text = $highlight.ImagePath
                    } else {
                        $TBImagePath.Text = ""
                    }
                    $TBImagePath.Location = New-Object System.Drawing.Point(500,8)
                    $TBImagePath.Add_LostFocus({ Save-GUIData })
                    $RandoHighlight.Controls.Add($TBImagePath)
                    $TBImagePath.Visible = $isPicture
                    
                    # Browse Button
                    $BTBrowse = New-Object System.Windows.Forms.Button
                    $BTBrowse.Name = "BTBrowse"
                    $BTBrowse.Text = "..."
                    $BTBrowse.Width = 30
                    $BTBrowse.Height = 23
                    $BTBrowse.Location = New-Object System.Drawing.Point(705,8)
                    $BTBrowse.Visible = $isPicture
                    $BTBrowse.Add_Click({
                        $dialog = New-Object System.Windows.Forms.OpenFileDialog
                        $dialog.Filter = "Image files (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png|All files (*.*)|*.*"
                        $dialog.Title = "Select Picture for Highlight"
                        if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                            $parent = $this.Parent
                            ($parent.Controls | where-object {$_.Name -eq "TBImagePath"}).Text = $dialog.FileName
                            Save-GUIData
                        }
                    })
                    $RandoHighlight.Controls.Add($BTBrowse)
                    
                    # Duration Label
                    $LBDuration = New-Object System.Windows.Forms.Label
                    $LBDuration.Name = "LBDuration"
                    $LBDuration.Text = "Duration (s)"
                    $LBDuration.AutoSize = $true
                    $LBDuration.Location = New-Object System.Drawing.Point(745,10)
                    $LBDuration.Visible = $isPicture
                    $RandoHighlight.Controls.Add($LBDuration)
                    
                    # Duration NumericUpDown
                    $NBDuration = New-Object System.Windows.Forms.NumericUpDown
                    $NBDuration.Name = "NBDuration"
                    $NBDuration.Width = 50
                    $NBDuration.Minimum = 1
                    $NBDuration.Maximum = 30
                    $NBDuration.Value = if($highlight.Duration) { $highlight.Duration } else { 5 }
                    $NBDuration.Location = New-Object System.Drawing.Point(830,8)
                    $NBDuration.Visible = $isPicture
                    $NBDuration.Add_ValueChanged({ Save-GUIData })
                    $RandoHighlight.Controls.Add($NBDuration)
                    
                    # Disable End time picker if picture mode (Start is used for timeline position)
                    if($isPicture) {
                        ($RandoHighlight.Controls | where-object {$_.Name -eq "TPEnd"}).Enabled = $false
                    }
                    
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
        
        # Start Label (changes meaning based on Picture checkbox)
        $LBStart = New-Object System.Windows.Forms.Label
        $LBStart.Name = "LBStart"
        $LBStart.Text = "Start"
        $LBStart.AutoSize = $true
        $LBStart.Location = New-Object System.Drawing.Point(5,10)
        $RandoHighlight.Controls.Add($LBStart)
        
        create-Timepick -Name "TPStart" -fromLeft 75 -fromTop 10 -AddTo  $RandoHighlight -Text "00:00:00"
        create-Label -Text "End" -fromLeft 200 -fromTop 10 -AddTo $RandoHighlight
        create-Timepick -Name "TPEnd" -fromLeft 275 -fromTop 10 -AddTo  $RandoHighlight -Text "00:00:00"
        
        # Picture Highlight Controls
        $CBPicture = New-Object System.Windows.Forms.CheckBox
        $CBPicture.Name = "CBPicture"
        $CBPicture.Text = "Picture"
        $CBPicture.Width = 80
        $CBPicture.Height = 20
        $CBPicture.Location = New-Object System.Drawing.Point(410,10)
        $CBPicture.Add_CheckedChanged({
            $parent = $this.Parent
            $isPicture = $this.Checked
            # Update label text based on mode
            $startLabel = $parent.Controls | where-object {$_.Name -eq "LBStart"}
            if($startLabel) {
                $startLabel.Text = if($isPicture) { "Insert At" } else { "Start" }
            }
            # Keep Start enabled for timeline position, disable only End time
            ($parent.Controls | where-object {$_.Name -eq "TPEnd"}).Enabled = !$isPicture
            ($parent.Controls | where-object {$_.Name -eq "BTBrowse"}).Visible = $isPicture
            ($parent.Controls | where-object {$_.Name -eq "TBImagePath"}).Visible = $isPicture
            ($parent.Controls | where-object {$_.Name -eq "LBDuration"}).Visible = $isPicture
            ($parent.Controls | where-object {$_.Name -eq "NBDuration"}).Visible = $isPicture
            Save-GUIData
        })
        $RandoHighlight.Controls.Add($CBPicture)
        
        # Image Path (hidden by default)
        $TBImagePath = New-Object System.Windows.Forms.TextBox
        $TBImagePath.Name = "TBImagePath"
        $TBImagePath.Width = 200
        $TBImagePath.ReadOnly = $true
        $TBImagePath.Location = New-Object System.Drawing.Point(500,8)
        $TBImagePath.Visible = $false
        $TBImagePath.Add_LostFocus({ Save-GUIData })
        $RandoHighlight.Controls.Add($TBImagePath)
        
        # Browse Button (hidden by default)
        $BTBrowse = New-Object System.Windows.Forms.Button
        $BTBrowse.Name = "BTBrowse"
        $BTBrowse.Text = "..."
        $BTBrowse.Width = 30
        $BTBrowse.Height = 23
        $BTBrowse.Location = New-Object System.Drawing.Point(705,8)
        $BTBrowse.Visible = $false
        $BTBrowse.Add_Click({
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.Filter = "Image files (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png|All files (*.*)|*.*"
            $dialog.Title = "Select Picture for Highlight"
            if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $parent = $this.Parent
                ($parent.Controls | where-object {$_.Name -eq "TBImagePath"}).Text = $dialog.FileName
                Save-GUIData
            }
        })
        $RandoHighlight.Controls.Add($BTBrowse)
        
        # Duration Label (hidden by default)
        $LBDuration = New-Object System.Windows.Forms.Label
        $LBDuration.Name = "LBDuration"
        $LBDuration.Text = "Duration (s)"
        $LBDuration.AutoSize = $true
        $LBDuration.Location = New-Object System.Drawing.Point(745,10)
        $LBDuration.Visible = $false
        $RandoHighlight.Controls.Add($LBDuration)
        
        # Duration NumericUpDown (hidden by default)
        $NBDuration = New-Object System.Windows.Forms.NumericUpDown
        $NBDuration.Name = "NBDuration"
        $NBDuration.Width = 50
        $NBDuration.Minimum = 1
        $NBDuration.Maximum = 30
        $NBDuration.Value = 5
        $NBDuration.Location = New-Object System.Drawing.Point(830,8)
        $NBDuration.Visible = $false
        $NBDuration.Add_ValueChanged({ Save-GUIData })
        $RandoHighlight.Controls.Add($NBDuration)
        
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
                write-host "`n=== Processing highlight groupbox ===" -ForegroundColor Cyan
                
                # Debug: Show all controls in this groupbox
                write-host "Controls in groupbox:" -ForegroundColor Gray
                foreach($ctrl in $highlightBox.Controls) {
                    write-host "  - Name: $($ctrl.Name), Type: $($ctrl.GetType().Name), Text/Value: $($ctrl.Text)" -ForegroundColor Gray
                }
                
                $StartTime = ($highlightBox.Controls | where-object {$_.Name -like "TPStart"}).Value
                $EndTime = ($highlightBox.Controls | where-object {$_.Name -like "TPEnd"}).Value
                $Comment = ($highlightBox.Controls | where-object {$_.Name -like "TBComment"}).Text
                $IsPicture = ($highlightBox.Controls | where-object {$_.Name -like "CBPicture"}).Checked
                $ImagePathControl = ($highlightBox.Controls | where-object {$_.Name -like "TBImagePath"})
                $ImagePath = if($ImagePathControl) { $ImagePathControl.Text } else { "" }
                $Duration = ($highlightBox.Controls | where-object {$_.Name -like "NBDuration"}).Value
            
                write-host "Extracted values:" -ForegroundColor Yellow
                write-host "  IsPicture: $IsPicture" -ForegroundColor Yellow
                write-host "  ImagePath: '$ImagePath'" -ForegroundColor Yellow
                write-host "  ImagePathControl found: $($ImagePathControl -ne $null)" -ForegroundColor Yellow
                if($ImagePath) {
                    write-host "  PathExists: $(Test-Path $ImagePath)" -ForegroundColor Yellow
                }
            
                if($IsPicture) {
                    # Picture highlight validation
                    if([string]::IsNullOrWhiteSpace($ImagePath)) {
                        write-host "Skipping picture highlight with no image path" -ForegroundColor Yellow
                        continue
                    }
                    if(!(Test-Path $ImagePath)) {
                        write-host "VALIDATION FAILED - Image file doesn't exist: $ImagePath" -ForegroundColor Red
                        [System.Windows.Forms.MessageBox]::Show("Picture highlight image not found:`n$ImagePath`n`nPlease select a valid image or delete this highlight.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                        return
                    }
                    
                    # Use Start time as insertion point in timeline
                    $InsertAt = [int]($StartTime.Hour * 3600 + $StartTime.Minute * 60 + $StartTime.Second)
                    
                    write-host "Picture highlight: $ImagePath at $InsertAt seconds, Duration: $Duration seconds, Comment: $Comment"
                    $manualHighlights += [PSCustomObject]@{
                        type = "picture"
                        imagePath = $ImagePath
                        duration = [int]$Duration
                        comment = $Comment
                        start = $InsertAt  # Timeline position for sorting
                        end = $InsertAt + [int]$Duration  # For sorting and display
                    }
                }
                else {
                    # Video highlight validation
                    # Convert time to seconds
                    $Start = [int]($StartTime.Hour * 3600 + $StartTime.Minute * 60 + $StartTime.Second)
                    $End = [int]($EndTime.Hour * 3600 + $EndTime.Minute * 60 + $EndTime.Second)
                
                    # Validate time range
                    if($End -le $Start) {
                        [System.Windows.Forms.MessageBox]::Show("Invalid highlight: End time must be after Start time.`nStart: $Start seconds, End: $End seconds", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                        return
                    }
                
                    write-host "Video highlight: Start: $Start seconds, End: $End seconds, Comment: $Comment"
                    $manualHighlights += [PSCustomObject]@{type="video"; start=$Start; end=$End; comment=$Comment}
                }
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