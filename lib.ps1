function create-Checkbox($name, $fromLeft, $fromTop, $AddTo)
{
    $CB = New-Object System.Windows.Forms.Checkbox
    $CB.Name = $name
    $CB.Width = 20
    $CB.Height = 20
    $CB.AutoSize = $false
    $CB.Location = New-Object System.Drawing.Point($fromLeft,$fromTop)
    
    $AddTo.Controls.Add($CB)
}

function create-Label($Text, $fromLeft, $fromTop, $AddTo)
{
    $LB = New-Object System.Windows.Forms.Label
    $LB.Text = $Text
    $LB.Location  = New-Object System.Drawing.Point($fromLeft,$fromTop)
    $LB.AutoSize = $true
    $AddTo.Controls.Add($LB)
    return $LB
}

function create-Timepick($Name, $Text, $fromLeft, $fromTop, $AddTo)
{
    $TP = New-Object System.Windows.Forms.DateTimePicker
    $TP.Name = $Name
    $TP.AutoSize = $true
    $TP.Format = [windows.forms.datetimepickerFormat]::time
    $TP.ShowUpDown = $true
    $TP.Size = New-Object System.Drawing.Size(120,23)
    $TP.Text = $Text
    $TP.Location = New-Object System.Drawing.Point($fromLeft,$fromTop)
    $AddTo.Controls.Add($TP)
}

function create-NumUpDown($Name, $Text, $fromLeft, $fromTop, $AddTo)
{
    $NB = New-Object System.Windows.Forms.NumericUpDown
    $NB.Name = $Name
    $NB.AutoSize = $true
    $NB.Size = New-Object System.Drawing.Size(100,23)
    $NB.Text = $Text
    $NB.Location = New-Object System.Drawing.Point($fromLeft,$fromTop)
    $AddTo.Controls.Add($NB)
}

function create-Button($text, $width, $height, $fromleft, $fromTop, $addTo)
{
    $BT = New-Object System.Windows.Forms.Button
    $BT.Size = New-Object System.Drawing.Size($width,$height)
    $BT.Text = "$text"
    $BT.Location = New-Object System.Drawing.Point($fromLeft,$FromTop)
    
    $addTo.Controls.Add($BT)
    return $bt

}

function create-GroupBox($Name, $Height, $fromLeft, $fromTop,$addTo)
{
    $GP = New-Object System.Windows.Forms.GroupBox
    $GP.Name = $Name
    $GP.Width = 550
    $GP.Height = $Height
    $GP.Font = New-Object System.Drawing.Font("Times New Roman",12)
    $GP.Location = New-Object System.Drawing.Point($fromLeft,$fromTop)
    $addTo.Controls.Add($GP)
}