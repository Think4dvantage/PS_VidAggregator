#Getting GUI Lib
. .\lib.ps1
#Getting VideoSummary Creator 
. .\VideoSummaryCreator

#File Selector
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
$FileBrowser.InitialDirectory = "D:\"
$FileBrowser.Filter = "mp4 files (*.mp4)|*.mp4|All files (*.*)|*.*";
$null = $FileBrowser.ShowDialog()
$VideoFile = $FileBrowser.FileName

#Create Form 
$SummaryGUI = New-Object System.Windows.Forms.Form
$SummaryGUI.Text ='Video Summary Creator'
$SummaryGUI.AutoSize = $false
$SummaryGUI.Width = 1200
$SummaryGUI.Height = 700
$SummaryGUI.AutoScroll = $true

#Create Title Label 
create-Label -Text ($VideoFile.Split("\"))[-1] -fromLeft 10 -fromTop 10 -AddTo $SummaryGUI -Type "Title"

#Add Highligts GroupBox
$Highlights = create-GroupBox -Name "GPHighlights" -Height 25 -width 1000 -fromLeft 5 -fromTop 50 -addTo $SummaryGUI

#PlusButton
$BTAddHighlight = create-Button -text "+" -width 70 -height 25 -fromleft 1015 -fromTop 60 -addTo $SummaryGUI

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
        create-textbox -Name "TBComment" -width 300 -height 25 -fromLeft 75 -FromTop 40 -addTo $RandoHighlight
        $Global:highFromTop += 78
        $SummaryGUI.Update()
    }
)

#Add RUN Button 
$BTNrun = create-Button -text "RUN" -width 100 -height 25 -fromleft 1015 -fromTop 5 -addTo $SummaryGUI

#Add RUN Function
$BTNrun.Add_Click(
    {
        write-host "RUN Button has been clicked"
        $manualHighlights = @()
        $manHigh = (($SummaryGUI.Controls | where-object {$_.Name -eq ("GPHighlights")}).Controls | where-object {$_.Name -eq ("HIGHLIGHTElement") -and $_.HasChildren -eq $true}).Controls
        foreach($High in $manHigh)
        {
            $Start = ($High | where-object {$_.Name -like "TPStart"}).Text
            $End = ($High | where-object {$_.Name -like "TPEnd"}).Text
            $Comment = ($High | where-object {$_.Name -like "TBComment"}).Text
            $manualHighlights += [PSCustomObject]@{start=$start; end=$end; comment=$comment}
        }
        write-host $manualHighlights

        #FIXIT - Returns lots of empty Stuff
        #aggregate-Video -SourceVideo $VideoFile -Highlights $manualHighlights -OutputLength 70 -PartLength 4 -OutputPath $VideoFile.Replace("FullFlight","Short")
    }
)

$SummaryGUI.ShowDialog()