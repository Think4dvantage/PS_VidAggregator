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
            BackgroundMusic = @{
                Enabled = $CBEnableMusic.Checked
                FilePath = $TBMusicPath.Text
                OverlayPercentage = $CBMusicOverlay.Text
            }
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
        
            # Load Background Music settings
            if($data.BackgroundMusic) {
                if($data.BackgroundMusic.Enabled -ne $null) {
                    $CBEnableMusic.Checked = $data.BackgroundMusic.Enabled
                }
                if($data.BackgroundMusic.FilePath) {
                    $TBMusicPath.Text = $data.BackgroundMusic.FilePath
                }
                if($data.BackgroundMusic.OverlayPercentage) {
                    $CBMusicOverlay.Text = $data.BackgroundMusic.OverlayPercentage
                } elseif($data.BackgroundMusic.Volume -ne $null) {
                    # Legacy support for old Volume setting
                    $CBMusicOverlay.SelectedIndex = 3  # Default to 40%
                }
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

#Add Background Music Section
create-Label -Text "Background Music" -fromLeft 460 -fromTop 80 -AddTo $SummaryGUI

# Checkbox to enable/disable background music
$CBEnableMusic = New-Object System.Windows.Forms.CheckBox
$CBEnableMusic.Name = "CBEnableMusic"
$CBEnableMusic.Text = "Enable"
$CBEnableMusic.Width = 70
$CBEnableMusic.Height = 20
$CBEnableMusic.Location = New-Object System.Drawing.Point(590,80)
$CBEnableMusic.Add_CheckedChanged({
    $TBMusicPath.Enabled = $this.Checked
    $BTBrowseMusic.Enabled = $this.Checked
    $BTBrowseMusicFolder.Enabled = $this.Checked
    $CBMusicOverlay.Enabled = $this.Checked
    Save-GUIData
})
$SummaryGUI.Controls.Add($CBEnableMusic)

# Music file/folder path textbox
$TBMusicPath = New-Object System.Windows.Forms.TextBox
$TBMusicPath.Name = "TBMusicPath"
$TBMusicPath.Width = 180
$TBMusicPath.ReadOnly = $true
$TBMusicPath.Location = New-Object System.Drawing.Point(670,80)
$TBMusicPath.Enabled = $false
$TBMusicPath.Add_LostFocus({ Save-GUIData })
$SummaryGUI.Controls.Add($TBMusicPath)

# Browse button for music file/folder
$BTBrowseMusic = New-Object System.Windows.Forms.Button
$BTBrowseMusic.Name = "BTBrowseMusic"
$BTBrowseMusic.Text = "File"
$BTBrowseMusic.Width = 40
$BTBrowseMusic.Height = 23
$BTBrowseMusic.Location = New-Object System.Drawing.Point(855,80)
$BTBrowseMusic.Enabled = $false
$BTBrowseMusic.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Audio files (*.mp3;*.wav;*.m4a;*.aac)|*.mp3;*.wav;*.m4a;*.aac|All files (*.*)|*.*"
    $dialog.Title = "Select Background Music File"
    $dialog.InitialDirectory = Join-Path $PSScriptRoot "resources"
    if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TBMusicPath.Text = $dialog.FileName
        Save-GUIData
    }
})
$SummaryGUI.Controls.Add($BTBrowseMusic)

# Browse folder button
$BTBrowseMusicFolder = New-Object System.Windows.Forms.Button
$BTBrowseMusicFolder.Name = "BTBrowseMusicFolder"
$BTBrowseMusicFolder.Text = "Folder"
$BTBrowseMusicFolder.Width = 50
$BTBrowseMusicFolder.Height = 23
$BTBrowseMusicFolder.Location = New-Object System.Drawing.Point(900,80)
$BTBrowseMusicFolder.Enabled = $false
$BTBrowseMusicFolder.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select Folder Containing Music Files"
    $dialog.SelectedPath = Join-Path $PSScriptRoot "resources"
    if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TBMusicPath.Text = $dialog.SelectedPath
        Save-GUIData
    }
})
$SummaryGUI.Controls.Add($BTBrowseMusicFolder)

# Music overlay percentage label and dropdown
create-Label -Text "Overlay %" -fromLeft 960 -fromTop 82 -AddTo $SummaryGUI
$CBMusicOverlay = New-Object System.Windows.Forms.ComboBox
$CBMusicOverlay.Name = "CBMusicOverlay"
$CBMusicOverlay.Width = 60
$CBMusicOverlay.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$CBMusicOverlay.Items.AddRange(@("10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%"))
$CBMusicOverlay.SelectedIndex = 3  # Default to 40%
$CBMusicOverlay.Location = New-Object System.Drawing.Point(1030,80)
$CBMusicOverlay.Enabled = $false
$CBMusicOverlay.Add_SelectedIndexChanged({ Save-GUIData })
$SummaryGUI.Controls.Add($CBMusicOverlay)

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

#Add "Add Music to Source" Button
$BTNAddMusicToSource = create-Button -text "Add Music to\nSource Video" -width 100 -height 40 -fromleft 1015 -fromTop 35 -addTo $SummaryGUI

#Add "Clear Music Cache" Button
$BTNClearCache = create-Button -text "Clear Music\nCache" -width 100 -height 35 -fromleft 1015 -fromTop 80 -addTo $SummaryGUI
$BTNClearCache.Add_Click({
    . "$PSScriptRoot\MusicFolderCache.ps1"
    Clear-MusicFolderCache
    [System.Windows.Forms.MessageBox]::Show("Music folder cache cleared. Next folder scan will rebuild the cache.", "Cache Cleared", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

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
        
            # Collect Background Music settings
            $musicSettings = $null
            if($CBEnableMusic.Checked) {
                try {
                $musicPath = $TBMusicPath.Text
                if([string]::IsNullOrWhiteSpace($musicPath)) {
                    [System.Windows.Forms.MessageBox]::Show("Background music is enabled but no music file/folder is selected.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                if(!(Test-Path $musicPath)) {
                    [System.Windows.Forms.MessageBox]::Show("Background music file/folder not found:`n$musicPath", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                
                # Determine if path is file or folder
                $selectedMusicFile = $null
                if(Test-Path $musicPath -PathType Container) {
                    # Check if it's OneDrive and warn user
                    if($musicPath -match "OneDrive") {
                        write-host "WARNING: OneDrive folder detected. This may be slow if files aren't downloaded locally." -ForegroundColor Yellow
                        $oneDriveWarning = [System.Windows.Forms.MessageBox]::Show(
                            "You selected a OneDrive folder. This may take a LONG time if files are cloud-only.`n`nRecommendations:`n• Use a local folder instead (copy music to D:\Music)`n• Or select a specific file with 'File' button`n• Or make OneDrive files 'Always keep on this device'`n`nContinue anyway?",
                            "OneDrive Warning",
                            [System.Windows.Forms.MessageBoxButtons]::YesNo,
                            [System.Windows.Forms.MessageBoxIcon]::Warning
                        )
                        if($oneDriveWarning -eq [System.Windows.Forms.DialogResult]::No) {
                            write-host "User cancelled OneDrive operation" -ForegroundColor Yellow
                            return
                        }
                    }
                    
                    # It's a folder - find best matching music file(s)
                    write-host "Searching for music files in folder: $musicPath" -ForegroundColor Cyan
                    write-host "Scanning folder and subfolders (this may take a moment for large libraries)..." -ForegroundColor Yellow
                    $musicFiles = Get-ChildItem -Path $musicPath -Recurse -Include *.mp3,*.wav,*.m4a,*.aac | Select-Object -ExpandProperty FullName
                    write-host "Found $($musicFiles.Count) music files" -ForegroundColor Green
                    
                    if($musicFiles.Count -eq 0) {
                        [System.Windows.Forms.MessageBox]::Show("No music files found in selected folder:`n$musicPath", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                        return
                    }
                    
                    
                    # Get FFmpeg paths for duration detection
                    . "$PSScriptRoot\FFmpegManager.ps1"
                    $ffmpegPaths = Ensure-FFmpeg
                    $ffprobe = $ffmpegPaths.FFprobe
                    $ffmpeg = $ffmpegPaths.FFmpeg
                    
                    # Use cached music folder analysis
                    . "$PSScriptRoot\MusicFolderCache.ps1"
                    $musicFilesWithDuration = Get-MusicFolderCache -FolderPath $musicPath -FFprobe $ffprobe
                    
                    if($musicFilesWithDuration.Count -eq 0) {
                        [System.Windows.Forms.MessageBox]::Show("No valid music files found or analyzed.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        return
                    }
                    
                    # Sort by duration
                    $musicFilesWithDuration = $musicFilesWithDuration | Sort-Object Duration
                    
                    # Try to find single file that fits
                    $bestMatch = $null
                    $bestDiff = [int]::MaxValue
                    
                    foreach($file in $musicFilesWithDuration) {
                        if($file.Duration -le $SummaryLength) {
                            $diff = $SummaryLength - $file.Duration
                            if($diff -lt $bestDiff) {
                                $bestDiff = $diff
                                $bestMatch = $file
                            }
                            write-host "  $($file.Name): $($file.Duration)s (diff: ${diff}s)" -ForegroundColor Gray
                        } else {
                            write-host "  $($file.Name): $($file.Duration)s (too long)" -ForegroundColor DarkGray
                        }
                    }
                    
                    if($bestMatch) {
                        $selectedMusicFile = $bestMatch.Path
                        write-host "Selected single music file: $($bestMatch.Name) (best fit for ${SummaryLength}s video)" -ForegroundColor Green
                    } else {
                        # No single file fits - need to concatenate multiple files
                        write-host "No single file fits. Concatenating multiple songs..." -ForegroundColor Yellow
                        
                        $selectedFiles = @()
                        $totalDuration = 0
                        
                        # Pick songs until we reach the target duration
                        foreach($file in $musicFilesWithDuration) {
                            if($totalDuration -ge $SummaryLength) {
                                break
                            }
                            $selectedFiles += $file
                            $totalDuration += $file.Duration
                            write-host "  Adding: $($file.Name) ($($file.Duration)s) - Total: ${totalDuration}s" -ForegroundColor Cyan
                        }
                        
                        if($selectedFiles.Count -eq 0) {
                            [System.Windows.Forms.MessageBox]::Show("Unable to find suitable music files.", "No Music", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                            return
                        }
                        
                        # Create concatenated music file
                        $tempMusicFile = Join-Path $env:TEMP "concatenated_music_$(Get-Date -Format 'yyyyMMdd_HHmmss').mp3"
                        write-host "Creating concatenated music file: $tempMusicFile" -ForegroundColor Cyan
                        
                        # Create concat file list
                        $concatListFile = Join-Path $env:TEMP "music_concat_list.txt"
                        $concatContent = ""
                        foreach($file in $selectedFiles) {
                            $concatContent += "file '" + $file.Path.Replace("'", "'\\''") + "'`n"
                        }
                        $concatContent | Set-Content -Path $concatListFile -Encoding UTF8
                        
                        # Concatenate music files
                        $concatArgs = "-f concat -safe 0 -i " + [char]34 + $concatListFile + [char]34 + " -c copy " + [char]34 + $tempMusicFile + [char]34 + " -y"
                        write-host "FFmpeg concat command: $concatArgs" -ForegroundColor Gray
                        $process = start-process -FilePath $ffmpeg -ArgumentList $concatArgs -PassThru -Wait -NoNewWindow
                        
                        if($process.ExitCode -ne 0 -or !(Test-Path $tempMusicFile)) {
                            write-host "Failed to concatenate music files" -ForegroundColor Red
                            [System.Windows.Forms.MessageBox]::Show("Failed to concatenate music files.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                            return
                        }
                        
                        $selectedMusicFile = $tempMusicFile
                        write-host "Successfully concatenated $($selectedFiles.Count) music files (total: ${totalDuration}s)" -ForegroundColor Green
                    }
                } else {
                    # It's a file - use directly
                    $selectedMusicFile = $musicPath
                    write-host "Using selected music file: $(Split-Path $musicPath -Leaf)"
                }
                }
                catch [System.Management.Automation.PipelineStoppedException] {
                    write-host "Music selection cancelled by user" -ForegroundColor Yellow
                    return
                }
                catch {
                    write-host "Error during music selection: $($_.Exception.Message)" -ForegroundColor Red
                    [System.Windows.Forms.MessageBox]::Show("Error selecting music:`n`n$($_.Exception.Message)", "Music Selection Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
                
                # Parse overlay percentage (e.g., "40%" -> 0.4)
                $overlayText = $CBMusicOverlay.Text
                $overlayPercent = [int]($overlayText -replace '%', '')
                $musicVolume = $overlayPercent / 100.0
                $originalVolume = 1.0 - $musicVolume
                
                $musicSettings = @{
                    FilePath = $selectedMusicFile
                    MusicVolume = $musicVolume
                    OriginalVolume = $originalVolume
                }
                
                # Generate music credits file
                . "$PSScriptRoot\GenerateMusicCredits.ps1"
                $creditsFile = Join-Path $VideoDirectory ($SummaryNameOnly + "_MusicCredits.txt")
                
                # Collect all music files used
                $usedMusicFiles = @()
                if($selectedMusicFile -eq $tempMusicFile -and (Test-Path $tempMusicFile)) {
                    # Multiple songs were concatenated - list all of them
                    foreach($file in $selectedFiles) {
                        $usedMusicFiles += $file.Path
                    }
                } else {
                    # Single song
                    $usedMusicFiles += $selectedMusicFile
                }
                
                Generate-MusicCredits -MusicFiles $usedMusicFiles -OutputPath $creditsFile
            }
        
            write-host "`nSummary Length: $SummaryLength seconds"
            write-host "Summary Name: $SummaryName"
            if($musicSettings) {
                write-host "Background Music: $($musicSettings.FilePath)"
                write-host "  Music Volume: $($musicSettings.MusicVolume * 100)%, Original Volume: $($musicSettings.OriginalVolume * 100)%"
            }

            # Call aggregate-Video function with collected data
            write-host "`nStarting video processing..."
            $result = aggregate-Video -SourceVideoPath $VideoFile -Highlights $manualHighlights -OutputLength $SummaryLength -PartLength 4 -OutputPath $SummaryName -BackgroundMusic $musicSettings
            
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

#Add "Add Music to Source Video" Button Click Handler
$BTNAddMusicToSource.Add_Click(
    {
        try {
            write-host "`n=== Add Music to Source Video ===" -ForegroundColor Cyan
            
            # Source the function
            . "$PSScriptRoot\AddMusicToVideo.ps1"
            
            # Prompt for music selection
            $musicDialog = New-Object System.Windows.Forms.Form
            $musicDialog.Text = "Add Music to Source Video"
            $musicDialog.Width = 550
            $musicDialog.Height = 250
            $musicDialog.StartPosition = "CenterScreen"
            $musicDialog.FormBorderStyle = "FixedDialog"
            $musicDialog.MaximizeBox = $false
            $musicDialog.MinimizeBox = $false
            
            # Instructions
            $lblInstructions = New-Object System.Windows.Forms.Label
            $lblInstructions.Text = "This will add background music to the FULL SOURCE VIDEO."
            $lblInstructions.Location = New-Object System.Drawing.Point(10, 10)
            $lblInstructions.AutoSize = $true
            $lblInstructions.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
            $musicDialog.Controls.Add($lblInstructions)
            
            # Music file/folder selection
            create-Label -Text "Music File/Folder:" -fromLeft 10 -fromTop 40 -AddTo $musicDialog
            
            $tbMusicPath = New-Object System.Windows.Forms.TextBox
            $tbMusicPath.Width = 300
            $tbMusicPath.Location = New-Object System.Drawing.Point(130, 40)
            $musicDialog.Controls.Add($tbMusicPath)
            
            $btnBrowseFile = New-Object System.Windows.Forms.Button
            $btnBrowseFile.Text = "File"
            $btnBrowseFile.Width = 40
            $btnBrowseFile.Location = New-Object System.Drawing.Point(435, 38)
            $btnBrowseFile.Add_Click({
                $dialog = New-Object System.Windows.Forms.OpenFileDialog
                $dialog.Filter = "Audio files (*.mp3;*.wav;*.m4a;*.aac)|*.mp3;*.wav;*.m4a;*.aac"
                $dialog.Title = "Select Music File"
                $dialog.InitialDirectory = Join-Path $PSScriptRoot "resources"
                if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $tbMusicPath.Text = $dialog.FileName
                }
            })
            $musicDialog.Controls.Add($btnBrowseFile)
            
            $btnBrowseFolder = New-Object System.Windows.Forms.Button
            $btnBrowseFolder.Text = "Folder"
            $btnBrowseFolder.Width = 50
            $btnBrowseFolder.Location = New-Object System.Drawing.Point(480, 38)
            $btnBrowseFolder.Add_Click({
                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $dialog.Description = "Select Music Folder"
                $dialog.SelectedPath = Join-Path $PSScriptRoot "resources"
                if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $tbMusicPath.Text = $dialog.SelectedPath
                }
            })
            $musicDialog.Controls.Add($btnBrowseFolder)
            
            # Overlay percentage
            create-Label -Text "Music Overlay %:" -fromLeft 10 -fromTop 80 -AddTo $musicDialog
            
            $cbOverlay = New-Object System.Windows.Forms.ComboBox
            $cbOverlay.Width = 80
            $cbOverlay.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $cbOverlay.Items.AddRange(@("10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%"))
            $cbOverlay.SelectedIndex = 3  # Default 40%
            $cbOverlay.Location = New-Object System.Drawing.Point(130, 80)
            $musicDialog.Controls.Add($cbOverlay)
            
            # Output name
            create-Label -Text "Output Name:" -fromLeft 10 -fromTop 120 -AddTo $musicDialog
            
            $tbOutputName = New-Object System.Windows.Forms.TextBox
            $tbOutputName.Width = 300
            $videoBaseName = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile)
            $tbOutputName.Text = $videoBaseName + "_WithMusic"
            $tbOutputName.Location = New-Object System.Drawing.Point(130, 120)
            $musicDialog.Controls.Add($tbOutputName)
            
            # OK button
            $btnOK = New-Object System.Windows.Forms.Button
            $btnOK.Text = "Process"
            $btnOK.Width = 80
            $btnOK.Location = New-Object System.Drawing.Point(350, 160)
            $btnOK.Add_Click({
                $musicDialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $musicDialog.Close()
            })
            $musicDialog.Controls.Add($btnOK)
            
            # Cancel button
            $btnCancel = New-Object System.Windows.Forms.Button
            $btnCancel.Text = "Cancel"
            $btnCancel.Width = 80
            $btnCancel.Location = New-Object System.Drawing.Point(450, 160)
            $btnCancel.Add_Click({
                $musicDialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                $musicDialog.Close()
            })
            $musicDialog.Controls.Add($btnCancel)
            
            # Show dialog
            $result = $musicDialog.ShowDialog()
            
            if($result -eq [System.Windows.Forms.DialogResult]::OK) {
                $musicPath = $tbMusicPath.Text
                $overlayText = $cbOverlay.Text
                $outputName = $tbOutputName.Text
                
                # Validate inputs
                if([string]::IsNullOrWhiteSpace($musicPath)) {
                    [System.Windows.Forms.MessageBox]::Show("Please select a music file or folder.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                
                if(!(Test-Path $musicPath)) {
                    [System.Windows.Forms.MessageBox]::Show("Music file/folder not found.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                
                # Get video length
                . "$PSScriptRoot\FFmpegManager.ps1"
                $ffmpegPaths = Ensure-FFmpeg
                $ffprobe = $ffmpegPaths.FFprobe
                $ffmpeg = $ffmpegPaths.FFmpeg
                
                start-process -FilePath $ffprobe -ArgumentList ("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + [char]34 + $VideoFile + [char]34) -NoNewWindow -RedirectStandardOutput C:\Windows\temp\sourcelength.txt -PassThru -Wait | Out-Null
                $sourceLength = [int]((get-content C:\Windows\Temp\sourcelength.txt).Split(".")[0])
                write-host "Source video length: $sourceLength seconds" -ForegroundColor Cyan
                
                # Select music file (same logic as summary)
                $selectedMusicFile = $null
                try {
                if(Test-Path $musicPath -PathType Container) {
                    # Check if it's OneDrive and warn user
                    if($musicPath -match "OneDrive") {
                        write-host "WARNING: OneDrive folder detected" -ForegroundColor Yellow
                        $oneDriveWarning = [System.Windows.Forms.MessageBox]::Show(
                            "OneDrive folder detected. This may be very slow for large music libraries.`n`nRecommendations:`n• Copy music to a local folder`n• Select a specific file instead`n• Ensure files are downloaded locally`n`nContinue?",
                            "OneDrive Warning",
                            [System.Windows.Forms.MessageBoxButtons]::YesNo,
                            [System.Windows.Forms.MessageBoxIcon]::Warning
                        )
                        if($oneDriveWarning -eq [System.Windows.Forms.DialogResult]::No) {
                            return
                        }
                    }
                    
                    write-host "Searching for music in folder: $musicPath" -ForegroundColor Cyan
                    write-host "Scanning folder and subfolders..." -ForegroundColor Yellow
                    $musicFiles = Get-ChildItem -Path $musicPath -Recurse -Include *.mp3,*.wav,*.m4a,*.aac | Select-Object -ExpandProperty FullName
                    write-host "Found $($musicFiles.Count) music files" -ForegroundColor Green
                    
                    if($musicFiles.Count -eq 0) {
                        [System.Windows.Forms.MessageBox]::Show("No music files found in folder.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        return
                    }
                    
                    # Use cached music folder analysis
                    . "$PSScriptRoot\MusicFolderCache.ps1"
                    $musicFilesWithDuration = Get-MusicFolderCache -FolderPath $musicPath -FFprobe $ffprobe
                    
                    if($musicFilesWithDuration.Count -eq 0) {
                        [System.Windows.Forms.MessageBox]::Show("No valid music files found.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        return
                    }
                    
                    $musicFilesWithDuration = $musicFilesWithDuration | Sort-Object Duration
                    
                    # Try single file
                    $bestMatch = $null
                    $bestDiff = [int]::MaxValue
                    foreach($file in $musicFilesWithDuration) {
                        if($file.Duration -le $sourceLength) {
                            $diff = $sourceLength - $file.Duration
                            if($diff -lt $bestDiff) {
                                $bestDiff = $diff
                                $bestMatch = $file
                            }
                        }
                    }
                    
                    if($bestMatch) {
                        $selectedMusicFile = $bestMatch.Path
                        write-host "Selected: $($bestMatch.Name)" -ForegroundColor Green
                    } else {
                        # Concatenate multiple
                        write-host "Concatenating multiple songs for ${sourceLength}s video..." -ForegroundColor Yellow
                        $selectedFiles = @()
                        $totalDuration = 0
                        
                        foreach($file in $musicFilesWithDuration) {
                            if($totalDuration -ge $sourceLength) { break }
                            $selectedFiles += $file
                            $totalDuration += $file.Duration
                            write-host "  Adding: $($file.Name) ($($file.Duration)s)" -ForegroundColor Cyan
                        }
                        
                        if($selectedFiles.Count -eq 0) {
                            [System.Windows.Forms.MessageBox]::Show("Unable to find suitable music.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                            return
                        }
                        
                        # Create concatenated file
                        $tempMusicFile = Join-Path $env:TEMP "source_music_$(Get-Date -Format 'yyyyMMdd_HHmmss').mp3"
                        $concatListFile = Join-Path $env:TEMP "source_music_concat.txt"
                        $concatContent = ""
                        foreach($file in $selectedFiles) {
                            $concatContent += "file '" + $file.Path.Replace("'", "'\\''") + "'`n"
                        }
                        $concatContent | Set-Content -Path $concatListFile -Encoding UTF8
                        
                        $concatArgs = "-f concat -safe 0 -i " + [char]34 + $concatListFile + [char]34 + " -c copy " + [char]34 + $tempMusicFile + [char]34 + " -y"
                        $process = start-process -FilePath $ffmpeg -ArgumentList $concatArgs -PassThru -Wait -NoNewWindow
                        
                        if($process.ExitCode -ne 0 -or !(Test-Path $tempMusicFile)) {
                            [System.Windows.Forms.MessageBox]::Show("Failed to concatenate music.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                            return
                        }
                        
                        $selectedMusicFile = $tempMusicFile
                        write-host "Concatenated $($selectedFiles.Count) files (${totalDuration}s)" -ForegroundColor Green
                    }
                } else {
                    $selectedMusicFile = $musicPath
                }
                }
                catch [System.Management.Automation.PipelineStoppedException] {
                    write-host "Music selection cancelled by user" -ForegroundColor Yellow
                    [System.Windows.Forms.MessageBox]::Show("Music selection cancelled.", "Cancelled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    return
                }
                catch {
                    write-host "Error during music selection: $($_.Exception.Message)" -ForegroundColor Red
                    [System.Windows.Forms.MessageBox]::Show("Error selecting music:`n`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
                
                # Calculate volumes
                $overlayPercent = [int]($overlayText -replace '%', '')
                $musicVolume = $overlayPercent / 100.0
                $originalVolume = 1.0 - $musicVolume
                
                # Create output path
                $videoDir = Split-Path $VideoFile -Parent
                $outputPath = Join-Path $videoDir ($outputName + ".mp4")
                
                # Generate music credits file
                . "$PSScriptRoot\GenerateMusicCredits.ps1"
                $creditsFile = Join-Path $videoDir ($outputName + "_MusicCredits.txt")
                
                # Collect all music files used
                $usedMusicFiles = @()
                if($selectedMusicFile -eq $tempMusicFile -and (Test-Path $tempMusicFile)) {
                    # Multiple songs were concatenated - list all of them
                    foreach($file in $selectedFiles) {
                        $usedMusicFiles += $file.Path
                    }
                } else {
                    # Single song
                    $usedMusicFiles += $selectedMusicFile
                }
                
                Generate-MusicCredits -MusicFiles $usedMusicFiles -OutputPath $creditsFile
                
                write-host "`nProcessing source video with music..." -ForegroundColor Green
                write-host "  Input: $VideoFile" -ForegroundColor Gray
                write-host "  Music: $selectedMusicFile" -ForegroundColor Gray
                write-host "  Output: $outputPath" -ForegroundColor Gray
                
                # Process video
                $success = Add-MusicToVideo -VideoPath $VideoFile -MusicPath $selectedMusicFile -OutputPath $outputPath -MusicVolume $musicVolume -OriginalVolume $originalVolume
                
                if($success) {
                    [System.Windows.Forms.MessageBox]::Show("Successfully added music to source video!`n`nOutput: $outputPath", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Failed to add music to video. Check console for details.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
        }
        catch {
            write-host "Error: $($_.Exception.Message)" -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show("An error occurred:`n`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
)

# Load existing data if available
Load-GUIData

$SummaryGUI.ShowDialog()