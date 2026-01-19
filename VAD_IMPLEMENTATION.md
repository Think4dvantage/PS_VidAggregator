# Voice Activity Detection (VAD) Implementation

## Problem Analysis

Your SRT transcript showed the core issue with Whisper-only speech detection:

- **Entries 1-251:** Mostly "I don't know" repeated (English auto-detection hallucinating)
- **Entries 252-1245:** Mostly "Go on", "Come on" repeated (vario beeps being transcribed)
- **Actual Speech:** Only ~10-15 real speech moments detected (entries 4-6, 9, 11-12, 14, 16-17, 55)

**Root Cause:** Whisper is a speech-to-text model, not a speech vs. noise detector. It tries to transcribe everything as speech, including vario beeping.

## Solution: Silero VAD Pre-filtering

**Silero VAD** is a neural network specifically designed to detect human voice patterns vs. background noise.

### How It Works

```
Original Audio → VAD Analysis → Voice Segments → Whisper Transcription → Final Result
                    ↓
              Filters out:
              - Vario beeping
              - Wind noise
              - Engine sounds
              - Other non-speech
```

### Benefits

1. **Eliminates Vario Hallucinations:** VAD detects that beeps are not human voice
2. **Faster Processing:** Only transcribes voice segments (not the full 60-minute video)
3. **Better Accuracy:** Whisper focuses on actual speech, not noise
4. **Automatic:** No manual configuration needed

## Installation

**Good News:** You already have everything needed!

Since you have PyTorch with CUDA installed (for GPU-accelerated Whisper), VAD will work automatically. The first time you run it, PyTorch will download the Silero VAD model (~5MB).

**To verify:**
```powershell
python -c "import torch; torch.hub.load(repo_or_dir='snakers4/silero-vad', model='silero_vad', force_reload=False); print('VAD Ready')"
```

## What Changed

### SpeechSegmentExtractor.ps1

1. **VAD Detection Check:** Automatically detects if PyTorch is available
2. **New Step 2a:** Runs VAD analysis before Whisper
3. **Optimized Step 2b:** Whisper only processes VAD-detected voice segments
4. **Progress Reporting:** Shows how many voice segments were detected

### Expected Output

**Console Output:**
```
=== Speech Segment Extraction ===
Using Python Whisper
GPU Detected: NVIDIA GeForce RTX 3060
Voice Activity Detection (VAD): ENABLED
  (Will pre-filter vario beeping before transcription)

Step 1: Extracting audio...
Audio extracted successfully

Step 2a: Running Voice Activity Detection...
  (Pre-filtering vario beeping and non-speech audio)
Detecting voice activity...
  Voice: 90.5s - 92.3s (1.8s)
  Voice: 125.7s - 128.1s (2.4s)
  Voice: 185.2s - 186.5s (1.3s)
Found 8 voice segments
Voice Activity Detection found 8 voice segments

Step 2b: Running Whisper ASR...
Transcribing 8 VAD-filtered voice segments...
  Transcribing segment 1/8: 90.5s - 92.3s
  Transcribing segment 2/8: 125.7s - 128.1s
  ...
Transcription complete! Found 8 speech segments
```

### Expected Results

Instead of 1245 entries (mostly hallucinations), you should see:
- ~5-15 voice segments detected by VAD
- Only those segments transcribed by Whisper
- Minimal "I don't know" or "Go on" hallucinations
- Actual speech properly captured

## Configuration

### VAD Threshold (Advanced)

The VAD threshold controls how strict voice detection is:

**Current Setting:** `0.6` (recommended)
- `0.3-0.4`: Lenient (may include some vario beeps)
- `0.5`: Default
- `0.6`: Strict (filters vario beeps well)
- `0.7-0.8`: Very strict (may miss some quiet speech)

**To adjust:** Edit line ~158 in SpeechSegmentExtractor.ps1:
```python
threshold=0.6,  # Change this value
```

### Minimum Speech Duration

**Current Setting:** 500ms (half second)
- Filters out very short sounds (likely not speech)
- Prevents single beeps from being detected

## Testing

1. Run the extraction with VAD enabled
2. Check console for "Voice Activity Detection: ENABLED"
3. Review the `_transcript.srt` file
4. Compare segment count: should be much lower (~10-20 instead of 1200+)

## Fallback Behavior

If VAD fails or is unavailable:
- Automatically falls back to full Whisper transcription
- Hallucination filter still removes repetitive phrases
- Results will be similar to previous runs

## Performance

**Processing Time Comparison:**

- **Without VAD:** Transcribe full 60-minute video
- **With VAD:** Transcribe only ~2-5 minutes of voice segments

**Expected speedup:** 10-20x faster transcription (after VAD analysis)

## Troubleshooting

**"Voice Activity Detection: DISABLED"**
- PyTorch not installed or not found
- Solution: Already installed in your case, should work

**"No voice detected"**
- VAD threshold too high
- Lower threshold to 0.5 or 0.4
- Or: Verify video has audible speech

**"Still getting vario hallucinations"**
- Check if VAD is actually running (look for Step 2a in console)
- Try increasing VAD threshold to 0.7
- Review `_transcript.srt` to see what VAD detected

## Alternative: Manual Highlight Selection

If VAD still doesn't work perfectly for your use case, consider the alternative workflow we discussed:

1. Record full flight video
2. Manually select highlight moments (you know when interesting things happened)
3. Use Whisper to add subtitles to those manual highlights
4. Concatenate highlights into summary video

This gives you full control over content selection while still benefiting from Whisper for subtitles.

## Next Steps

1. **Test the updated script:** Run speech extraction on your video
2. **Check console output:** Verify VAD is enabled and detecting voice segments
3. **Review transcript:** Open the `_transcript.srt` file to see results
4. **Compare to previous run:** Should have far fewer entries and no repetitive hallucinations

If results are good, you have a working automated speech extraction system! If not, we can adjust VAD parameters or implement the manual highlight workflow instead.
