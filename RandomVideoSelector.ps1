$Vids = get-childitem -path "D:\Insta360Parts" | where-object Name -notlike "done-*"

foreach($vid in $vids)
 {
    $randoVid = $vids[(get-random -Maximum $vids.count)]
    read-host -Prompt ("Take: " + $randoVid.FullName)
    rename-item -path $randoVid.FullName -NewName ("done-" + $randoVid.Name) 
    $vids = $vids | where-object name -ne $radoVid.Name
 }