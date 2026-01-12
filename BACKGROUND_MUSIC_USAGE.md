# Background Music Feature

## Overview
The background music feature allows you to add a soundtrack to:
1. **Video summaries** (with highlights)
2. **Full source videos** (entire original video)

The music is mixed with the original video audio at a configurable overlay percentage (e.g., 40% music / 60% original).

The system can either:
- **Auto-select** the best-fitting music from a folder based on video length
- **Use a specific file** you manually select
- **Concatenate multiple songs** if no single song is long enough

## For Video Summaries

### 1. Enable Background Music
In the GUI, locate the "Background Music" section (right side, below Summary Name):
- Check the "Enable" checkbox to activate background music

### 2. Select Music Source

You have two options:

#### Option A: Auto-Select from Folder (Recommended)
- Click the **"Folder"** button
- Select a folder containing your music files
- The system will automatically choose the song that best fits your video length
- **Smart Selection Logic:**
  - Scans folder and all subfolders for music files (MP3, WAV, M4A, AAC)
  - Analyzes the duration of each music file
  - Selects the file that is **as long or slightly shorter** than your video
  - **Never selects music longer than the video**
  - Displays analysis results in console

#### Option B: Manual File Selection
- Click the **"File"** button to select a specific audio file
- Supported formats: MP3, WAV, M4A, AAC
- The browser will default to the `resources/` folder
- Selected file will be used regardless of length (will loop if shorter)

### 3. Adjust Overlay Percentage
- Use the **"Overlay %"** dropdown to set the mix level
- Available options: 10%, 20%, 30%, 40%, 50%, 60%, 70%, 80%
- **Default: 40%** (40% music, 60% original video audio)
- **Lower values (10-30%):** Music is subtle background
- **Medium values (40-50%):** Balanced mix
- **Higher values (60-80%):** Music is prominent

### 4. Process Video
- Add your highlights as normal
- Click RUN to generate the video with background music
- The music will loop throughout the entire video duration
- Original video audio is preserved and mixed at the specified ratio

## For Full Source Videos

### 1. Click "Add Music to Source Video" Button
Located below the RUN button in the main GUI.

### 2. Configure Music in Dialog
A dialog will appear with the following options:
- **Music File/Folder:** Select individual file or folder for auto-selection
- **Music Overlay %:** Choose overlay percentage (default 40%)
- **Output Name:** Name for the output video (default: OriginalName_WithMusic)

### 3. Process
- Click "Process" to start
- The system will:
  - Auto-select music if folder chosen (same logic as summaries)
  - Concatenate multiple songs if needed for long videos
  - Copy video stream (no re-encoding = fast!)
  - Mix audio streams at specified overlay ratio
  - Create new file with music

### Use Cases for Source Video Music
- **Upload to YouTube:** Create music version for copyright-free uploads
- **Social Media:** Add background music for more engaging content
- **Archive:** Create multiple versions with different music
- **Long Videos:** Perfect for multi-hour videos (auto-concatenates songs)

## Music Selection Examples

### Example 1: Auto-Select Single Song
```
Video Summary Length: 3 minutes (180 seconds)
Music Folder: D:\Music\Background\

Found files:
  - Calm_Skies.mp3: 175s (diff: 5s) ✓ SELECTED
  - Energetic_Beat.mp3: 210s (too long, skipping)
  - Short_Loop.mp3: 60s (diff: 120s)
  - Perfect_Flight.mp3: 180s (diff: 0s) ← Would be selected if found first

Result: Uses "Calm_Skies.mp3" (closest match without exceeding)
```

### Example 2: Auto-Concatenate Multiple Songs
```
Video Summary Length: 10 minutes (600 seconds)
Music Folder: D:\Music\Short\

Found files:
  - Song1.mp3: 180s (too short alone)
  - Song2.mp3: 200s (too short alone)
  - Song3.mp3: 150s (too short alone)
  - Song4.mp3: 220s (too short alone)

Auto-concatenation:
  Adding: Song4.mp3 (220s) - Total: 220s
  Adding: Song2.mp3 (200s) - Total: 420s
  Adding: Song1.mp3 (180s) - Total: 600s ✓ TARGET REACHED

Result: Creates temporary concatenated file with 3 songs (600s total)
```

### Example 3: Long Source Video
```
Source Video Length: 2 hours (7200 seconds)
Music Folder: D:\Music\Library\

Found 50 files, longest is 300s (5 minutes)

Auto-concatenation:
  Adding 24 songs to reach 7200+ seconds
  Creates single concatenated music track
  
Result: Music plays throughout entire 2-hour video
```

### Example 4: Manual Selection
```
Video Summary Length: 3 minutes (180 seconds)
Selected File: Epic_Soundtrack.mp3 (5 minutes)

Result: Music will play for 3 minutes then fade out with video
```

## Best Practices

### Folder Organization
Organize your music library by mood/genre:
```
resources/
  music/
    ambient/
      - calm_1.mp3 (2:30)
      - calm_2.mp3 (3:15)
      - calm_3.mp3 (4:00)
    energetic/
      - upbeat_1.mp3 (2:00)
      - upbeat_2.mp3 (3:30)
    epic/
      - dramatic_1.mp3 (5:00)
      - dramatic_2.mp3 (4:30)
```

Then select the appropriate folder based on your video's mood!

### Music Recommendations
- **For paragliding videos:** Ambient, calm, or inspiring instrumental tracks
- **For action videos:** Energetic, upbeat tracks with rhythm
- **Avoid:** Songs with vocals (competes with video audio)
- **Copyright:** Use royalty-free music only

### Overlay Percentage Guidelines
- **10-20%:** Very subtle music, mostly original audio (talking, important sounds)
- **30-40%:** Balanced mix, music enhances without overpowering (recommended)
- **50-60%:** Music is prominent, original audio supporting
- **70-80%:** Music dominates, use only if original audio is unimportant

## Technical Details

### Audio Mixing
- Music is looped indefinitely (`-stream_loop -1`)
- **Both streams** have volume adjusted:
  - Original audio: `volume={1 - overlay%}`
  - Music: `volume={overlay%}`
- Mixed using `amix` filter with `duration=first` (music stops when video ends)
- Final audio: AAC codec, 192k bitrate

### Smart Selection Algorithm
1. Recursively scan folder for: `*.mp3`, `*.wav`, `*.m4a`, `*.aac`
2. Use FFprobe to detect duration of each file
3. Filter out files longer than video length
4. Select file with smallest duration difference (closest fit)
5. If no files fit (all too long), show error and ask user to select different folder or specific file

### Settings Persistence
- Music settings are saved in the archive JSON files
- Settings reload automatically when reopening the same video
- Each video can have different music settings
- Stores: Enabled state, File/Folder path, Overlay percentage

## Troubleshooting

### "No music files found in folder"
- **Cause:** Folder doesn't contain supported audio files
- **Solution:** 
  - Ensure folder contains MP3, WAV, M4A, or AAC files
  - Check subfolders (they're scanned automatically)

### "Unable to find suitable music"
- **Cause:** Rare edge case with very specific durations
- **Solution:** 
  - Add more variety of song lengths to your folder
  - Use "File" button to manually select a song

### Music concatenation failed
- **Cause:** FFmpeg error during concatenation
- **Solution:**
  - Check console output for details
  - Ensure all music files are valid and not corrupted
  - Try selecting a different folder or individual file

### Music Not Playing
- Verify the file/folder path is correct and exists
- Check if "Enable" checkbox is checked
- Ensure selected file is a valid audio format
- Check FFmpeg console output for errors

### Music Too Loud/Quiet
- Adjust the "Overlay %" dropdown
- Remember: 40% = 40% music + 60% original
- Try different percentages and re-run

### Can't Hear Original Audio
- Lower the overlay percentage (try 20-30%)
- Ensure your original video has audio (check in media player)

### Folder Selection Shows Wrong Results
- Ensure folder path is saved correctly (check in archive JSON)
- The folder must contain audio files (MP3, WAV, M4A, AAC)
- Subfolders are scanned automatically

### Source Video Processing is Slow
- **For very long videos:** Processing can take time
- **Speed tip:** Video stream is copied (not re-encoded), only audio is processed
- **Progress:** Check console output for FFmpeg progress

### Concatenated Music Has Gaps
- This shouldn't happen with proper audio files
- Try using files with the same format/bitrate
- Or manually select a single long music file instead

## Advanced Tips

### For Very Long Videos (2+ hours)
1. Create a dedicated music folder with many songs
2. Use "Folder" selection for auto-concatenation
3. Mix of different songs prevents monotony
4. Lower overlay % (20-30%) keeps it subtle

### For Professional Results
1. Use high-quality audio files (320kbps MP3 or WAV)
2. Keep overlay at 30-40% for balanced mix
3. Choose music that matches video mood
4. Test with different overlay % to find sweet spot

### Performance Optimization
- **Summary videos:** Re-encodes entire video (slower)
- **Source videos:** Copies video stream (much faster)
- For testing, use source video music feature first

## FFmpeg Command Details

When background music is enabled, the following additions are made:

**Input (looped music):**
```
-stream_loop -1 -i "path/to/selected_music.mp3"
```

**Filter (with overlay percentage, e.g., 40% music / 60% original):**
```
[aout]volume=0.6[orig];
[musicInputIndex]volume=0.4[music];
[orig][music]amix=inputs=2:duration=first:dropout_transition=2[finalout]
```

**Map:**
```
-map "[finalout]"
```

This ensures:
- Both audio streams are volume-adjusted to the correct ratio
- Music loops throughout the video
- Music stops when video ends (doesn't continue playing)
- Smooth mixing with dropout transition
