# Picture Highlights Feature - Testing Guide

## What's New

Picture highlights have been added! You can now insert still images into your video summaries alongside video clips.

## How to Use

### 1. Adding a Picture Highlight

1. Run `GUI.ps1` and select your video
2. Click the **+** button to add a highlight
3. Check the **"Picture"** checkbox
4. Click the **...** button to browse and select an image (JPG, JPEG, or PNG)
5. Set the duration (1-30 seconds) - defaults to 5 seconds
6. Add an optional comment (will appear as text overlay on the image)
7. The Start/End time pickers are disabled for picture highlights

### 2. Mixing Video and Picture Highlights

You can freely mix video clips and picture highlights:
- Video highlights: Shows clips from the source video
- Picture highlights: Shows your selected images for the specified duration
- All highlights are processed in the order they appear in the GUI

### 3. Saved Data

Picture highlights are saved to the archive JSON file with this structure:
```json
{
    "Type": "picture",
    "ImagePath": "D:\\Photos\\amazing_view.jpg",
    "Duration": 5,
    "Comment": "Amazing mountain view"
}
```

## Testing Checklist

### Basic Tests
- [ ] Add a picture highlight without selecting an image (should show error when clicking RUN)
- [ ] Add a picture highlight with valid image (should work)
- [ ] Set picture duration to different values (1s, 5s, 15s, 30s)
- [ ] Add comment to picture highlight (should appear as overlay)
- [ ] Mix video and picture highlights (should concatenate properly)
- [ ] Save and reload - picture highlights should persist

### Advanced Tests
- [ ] Use different image formats (JPG, PNG)
- [ ] Use images with different aspect ratios (portrait, landscape, square)
- [ ] Use very high resolution images (should scale down)
- [ ] Use very low resolution images (should scale up with black bars)
- [ ] Multiple picture highlights in one video
- [ ] Picture highlight at beginning, middle, and end of summary

### Edge Cases
- [ ] Picture highlight with deleted/moved image file (should show error)
- [ ] Picture highlight with special characters in path
- [ ] Very long comment text on picture (check if readable)
- [ ] Picture duration longer than remaining summary time
- [ ] Only picture highlights, no video clips

## Example Workflow

1. **Scenario**: Create a 2-minute summary with intro image, video clips, and outro image

   - Add picture highlight: Your logo/intro (5 seconds)
   - Add video highlights: Best moments from flight (80 seconds total)
   - Add picture highlight: Group photo at landing (5 seconds)
   - Summary length: 00:02:00
   - The tool will auto-fill remaining time with video clips

2. **Expected Result**: 
   - 5s intro image
   - Mix of your selected clips + auto-generated filler
   - 5s outro image
   - 5s end screen ("Like & Subscribe")
   - Total: ~2 minutes

## Technical Details

### Image Processing
- Images are scaled to match source video resolution
- Aspect ratio preserved with black padding (pillarbox/letterbox)
- Converted to YUV420P format for compatibility
- Set to 29.97 FPS to match video

### FFmpeg Command Structure
```powershell
-i source.mp4                              # [0] Source video
-loop 1 -t 5 -i picture1.jpg               # [1] First picture
-f lavfi -t 5 -i anullsrc                  # [2] Silent audio for picture
-loop 1 -t 3 -i picture2.jpg               # [3] Second picture
-f lavfi -t 3 -i anullsrc                  # [4] Silent audio for picture
-filter_complex "[1]scale=3840:2160:...[p0],[0]trim=...[p1],..."
```

### Resolution Detection
The tool automatically detects your source video resolution and scales images to match. If detection fails, it defaults to 3840x2160 (4K).

## Troubleshooting

### "Picture file not found" error
- Ensure the image path is valid
- Check file wasn't moved/deleted after selection
- Verify file extension is supported (.jpg, .jpeg, .png)

### Images appear stretched/squashed
- This shouldn't happen - images maintain aspect ratio with black bars
- If it does occur, please report with video resolution details

### FFmpeg encoding fails
- Check console output for specific FFmpeg error
- Verify image files are not corrupted
- Try converting image to JPG format first

### Very slow processing
- High resolution images (>8K) may be slow to process
- Consider resizing images before adding to video
- Multiple picture highlights increase processing time

## Performance Notes

- Picture highlights add minimal processing time compared to video clips
- Image loading happens once at encoding start
- No difference between 1s and 30s picture duration in processing time
- End screen (if exists) is also a picture highlight internally

## Future Enhancements (Not Yet Implemented)

- [ ] Picture transitions (fade in/out, dissolve)
- [ ] Pan & zoom effects (Ken Burns style)
- [ ] Multiple images in slideshow mode
- [ ] Picture-in-picture overlays
- [ ] Drag & drop image selection
- [ ] Image preview in GUI
