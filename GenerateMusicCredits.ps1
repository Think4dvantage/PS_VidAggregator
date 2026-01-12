function Generate-MusicCredits {
    [CmdletBinding()]
    param (
        [array]$MusicFiles,  # Array of music file paths
        [string]$OutputPath  # Where to save the credits text file
    )
    
    begin {
        write-host "Generating music credits..." -ForegroundColor Cyan
    }
    
    process {
        $credits = "Music Credits:`n`n"
        
        foreach($musicFile in $MusicFiles) {
            # Extract song name from filename (remove extension and path)
            $songName = [System.IO.Path]::GetFileNameWithoutExtension($musicFile)
            
            # Clean up the song name (remove common prefixes, numbers, etc.)
            # Remove leading numbers and dashes/underscores
            $songName = $songName -replace '^[\d_-]+', ''
            # Replace underscores and dashes with spaces
            $songName = $songName -replace '[_-]', ' '
            # Trim whitespace
            $songName = $songName.Trim()
            
            $credits += "Song Title: $songName`n"
            $credits += "`n"
            $credits += "Artist: StreamBeats by Harris Heller`n"
            $credits += "`n"
            $credits += "Source: https://www.streambeats.com`n"
            $credits += "`n"
            $credits += "License: Use licensed under Senpai Music Group, LLC`n"
            $credits += "`n"
            $credits += "---`n`n"
        }
        
        # Remove last separator
        $credits = $credits.TrimEnd("`n---`n`n")
        
        # Save to file
        try {
            $credits | Set-Content -Path $OutputPath -Encoding UTF8
            write-host "Music credits saved to: $OutputPath" -ForegroundColor Green
            
            # Also copy to clipboard for convenience
            try {
                $credits | Set-Clipboard
                write-host "Credits also copied to clipboard!" -ForegroundColor Green
            }
            catch {
                write-host "Could not copy to clipboard (but file was saved)" -ForegroundColor Yellow
            }
            
            return $true
        }
        catch {
            write-host "Error saving credits file: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    end {
        write-host "Music credits generation complete." -ForegroundColor Cyan
    }
}
