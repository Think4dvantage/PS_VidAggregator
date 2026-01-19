# Speech Segment Extraction Feature

## Overview
This feature uses OpenAI's Whisper AI model combined with Voice Activity Detection (VAD) to detect spoken language in videos and automatically extract only the segments containing speech. The VAD pre-filters audio to distinguish actual human voice from background noise (like vario beeping), then Whisper transcribes only the voice segments.

## Requirements

### Required: Python Whisper
1. **Install Python** (3.8 or higher)
   - Download from https://www.python.org/downloads/
   - Make sure to check "Add Python to PATH" during installation

2. **Install Whisper**
   ```powershell
   pip install openai-whisper
   ```

3. **Install PyTorch with CUDA support** (for GPU acceleration - HIGHLY RECOMMENDED)
   ```powershell
   pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
   ```
   *Note: CUDA support makes Whisper 10-20x faster! Highly recommended if you have an NVIDIA GPU.*

### Recommended: Voice Activity Detection (VAD)
**NEW: Filters out vario beeping and background noise!**

The system automatically detects if PyTorch is installed (from step 3 above). If PyTorch is available, Silero VAD will be used to pre-filter audio before Whisper transcription. This dramatically improves results for paragliding videos with vario interference.

**VAD Benefits:**
- Filters vario beeping automatically
- Distinguishes human voice from background noise
- Reduces Whisper hallucinations
- Faster processing (only transcribes voice segments)
- More accurate speech detection

**How VAD Works:**
1. Silero VAD analyzes the full audio track
2. Detects segments containing human voice patterns (not beeping)
3. Only those segments are sent to Whisper for transcription
4. Result: Clean speech extraction without vario hallucinations

## How to Use

1. **Open the GUI**
   - Run `GUI.ps1` and select your video file

2. **Click "Extract Speech Segments"** button
   - Located on the right side of the GUI

3. **Configure Settings**
   - **Model Selection:**
     - `tiny` - Fastest, less accurate (good for testing)
     - `base` - **Recommended** for most use cases
     - `small` - More accurate, slower
     - `medium` - High accuracy, much slower
     - `large` - Highest accuracy, very slow
   
   - **Minimum Silence Gap:**
     - Default: 1.0 seconds
     - Segments closer than this will be merged
     - Increase for fewer, longer segments
     - Decrease to keep shorter pauses
   
   - **Language (Optional):**
     - Leave empty for auto-detection
     - Use language codes: `en` (English), `de` (German), `es` (Spanish), `fr` (French), etc.
     - For Swiss German, try `de` or leave empty

4. **Wait for Processing**
   - **Step 1:** Audio extraction
   - **Step 2a:** Voice Activity Detection (if enabled) - filters vario beeping
   - **Step 2b:** Whisper transcription - only on voice segments
   - **Step 3:** Parse timestamps and filter hallucinations
   - **Step 4:** Concatenate video segments with GPU acceleration
   - First run: Downloads Whisper model (takes time)
   - Progress will be shown in the PowerShell console

5. **Output**
   - Creates: `YourVideo_SpeechOnly.mp4` (video with speech segments)
   - Creates: `YourVideo_SpeechOnly_transcript.srt` (transcript for review)
   - Original video remains unchanged
   
6. **Review the Transcript**
   - Open the `_transcript.srt` file to see what was detected
   - Use this to verify speech detection quality
   - If mostly hallucinations, VAD threshold may need adjustment

## Model Comparison

| Model  | Size  | Speed    | Accuracy | Use Case |
|--------|-------|----------|----------|----------|
| tiny   | ~75MB | Fastest  | Good     | Quick tests, live captions |
| base   | ~140MB| Fast     | Very Good| **Most videos (recommended)** |
| small  | ~460MB| Medium   | Excellent| Professional projects |
| medium | ~1.5GB| Slow     | Superior | High-quality transcription |
| large  | ~2.9GB| Very Slow| Best     | Critical accuracy needs |

## Troubleshooting

### "Whisper not found"
- **Python Whisper:** Run `pip install openai-whisper` in PowerShell
- **Test installation:** `python -c "import whisper; print('OK')"`

### "No speech detected" or "Output is mostly vario beeping"
- **Solution 1:** VAD should be enabled (install PyTorch as shown above)
- **Solution 2:** Check if VAD is running (look for "Voice Activity Detection: ENABLED")
- **Solution 3:** Adjust vario volume settings on your device
- **Solution 4:** Try forcing language detection: set Language to `de` for German/Swiss German
- **Check:** Review the `_transcript.srt` file to see what was detected

### "Detecting English instead of Swiss German"
- Set Language field to `de` instead of auto-detect
- VAD with `de` language works better for Swiss German dialect

### Slow Processing
- Use smaller model (`tiny` or `base`)
- Enable GPU acceleration (see installation steps above)
- VAD makes processing faster by only transcribing voice segments

### Out of Memory Error
- Use smaller model
- Process shorter videos
- Close other applications

### Vario Beeps Still Getting Through
- Check if "Voice Activity Detection: ENABLED" appears in console
- If VAD is disabled, install PyTorch: `pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118`
- VAD threshold can be adjusted in the Python script (default: 0.6)

## Technical Details

### How It Works
1. **Audio Extraction:** Extracts audio from video as 16kHz WAV with volume normalization
2. **Voice Activity Detection (VAD):** Silero VAD pre-filters audio to find human voice segments
   - Uses neural network trained to detect voice vs noise
   - Filters out vario beeping, wind noise, and other non-speech audio
   - Returns precise timestamps of voice-only segments
3. **Speech Recognition:** Whisper transcribes only the VAD-detected voice segments
4. **Segment Detection:** Identifies all speech segments with precise timing
5. **Hallucination Filtering:** Removes repetitive false transcriptions (e.g., vario beeps transcribed as "Go on")
6. **Segment Merging:** Combines nearby segments (within silence gap threshold)
7. **Video Concatenation:** Uses FFmpeg filter_complex with GPU acceleration to cut and join video segments

### VAD vs Whisper-Only
**Without VAD (old method):**
- Whisper transcribes entire audio track
- Vario beeps transcribed as "I don't know", "Go on", "Come on", etc.
- Many false positives (hallucinations)
- Longer processing time

**With VAD (new method):**
- VAD pre-filters to find only human voice
- Whisper only processes voice segments
- Dramatically fewer hallucinations
- Faster processing (less audio to transcribe)
- Better accuracy for Swiss German and dialects

### Output Format
- Video Codec: H.264 (NVENC GPU if available, libx264 CPU fallback)
- Audio Codec: AAC (192kbps)
- Preset: medium (balance of speed and quality)
- CRF: 23 (good quality)

## Performance Tips

1. **First Run:** Model download takes time but only happens once
2. **GPU Acceleration:** Whisper automatically uses GPU if available (CUDA)
3. **Batch Processing:** Process multiple videos by running the extraction sequentially
4. **Model Caching:** Models are cached after first use for faster subsequent runs

## Examples

### Basic Usage (Auto-detect language, base model)
```powershell
. .\SpeechSegmentExtractor.ps1
Extract-SpeechSegments -SourceVideoPath "D:\Videos\MyVideo.mp4" -OutputPath "D:\Videos\MyVideo_SpeechOnly.mp4"
```

### Advanced Usage (Specific language, custom gap)
```powershell
Extract-SpeechSegments -SourceVideoPath "D:\Videos\MyVideo.mp4" `
                       -OutputPath "D:\Videos\MyVideo_SpeechOnly.mp4" `
                       -WhisperModel "small" `
                       -Language "de" `
                       -MinSilenceGap 0.5
```

## Credits
- **Whisper AI:** OpenAI (https://github.com/openai/whisper)
- **FFmpeg:** https://ffmpeg.org/
