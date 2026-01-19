# PS_VidAggregator - PowerShell Video Aggregator

A Windows PowerShell tool for creating highlight summaries from long videos with automated speech extraction using Whisper AI.

## Features

- 🎬 **Highlight Summaries**: Mark interesting moments and create condensed highlight reels
- 🗣️ **Speech Extraction**: Automatically extract segments with spoken language using Whisper AI
- 🎵 **Background Music**: Add music to your summaries with smart auto-selection
- 🚁 **Vario Filtering**: Special Voice Activity Detection (VAD) to filter out paragliding vario beeping
- 🎯 **Smart Deduplication**: Combines manual highlights and speech segments intelligently
- 💾 **Auto-Save**: All highlights saved to JSON files for later editing
- 🎨 **Custom Overlays**: Add text comments to highlight segments
- 🖥️ **GPU Acceleration**: Automatic NVIDIA GPU detection for hardware encoding

## Quick Start

### Installation

1. **Clone the repository**
   ```powershell
   git clone https://github.com/yourusername/PS_VidAggregator.git
   cd PS_VidAggregator
   ```

2. **Run the GUI**
   ```powershell
   .\GUI.ps1
   ```

3. **First Run Setup** (Automatic)
   - FFmpeg will auto-download from GitHub
   - Python 3.13 will auto-install via winget (if not present)
   - Required Python packages will auto-install via pip:
     - openai-whisper (AI speech recognition)
     - torch with CUDA support (GPU acceleration)
     - soundfile, scipy (audio processing)
     - packaging (dependency management)

> **Note**: If Python installation requires a PowerShell restart, the tool will notify you. Simply restart PowerShell and run `.\GUI.ps1` again.

### Prerequisites (All Auto-Installed)

- **Windows OS** (PowerShell 5.1+)
- **Internet connection** (for first-time setup)
- **Optional**: NVIDIA GPU with CUDA for faster processing

The tool automatically installs:
- FFmpeg (video processing)
- Python 3.13+ with pip
- Python packages (whisper, torch, soundfile, scipy, packaging)

## Usage

### Creating a Basic Highlight Summary

1. **Launch** the tool: `.\GUI.ps1`
2. **Select video** file (or multiple files to concatenate)
3. **Mark highlights**:
   - Set start time (HH:MM:SS)
   - Set end time (HH:MM:SS)
   - Optional: Add comment overlay text
   - Click "+" to add more highlights
4. **Set summary length** (auto-calculated from highlights)
5. **Click "Create Summary"** to generate `VideoName_Summary.mp4`

### Speech Extraction (Automatic)

The "Summary & Speech" button combines your manual highlights with automatically detected speech segments:

1. **Mark manual highlights** (optional - can be empty)
2. **Click "Summary & Speech"** button
3. The tool will:
   - Use Silero VAD to detect voice activity (filters vario beeping)
   - Use Whisper AI to transcribe Swiss German → German
   - Combine manual highlights + speech segments
   - Remove overlapping segments
   - Create `VideoName_Summary_WithSpeech.mp4`

> **Swiss German Support**: The speech extraction is optimized for Swiss German paragliding videos, with special filtering for vario beeping and wind noise.

### Background Music

1. **Enable background music** checkbox
2. **Select music**:
   - **Folder**: Auto-selects best-fitting song from folder
   - **File**: Manually choose specific audio file
3. **Adjust overlay %** (default: 40%)
4. **Process video** - music will be mixed with original audio

See [BACKGROUND_MUSIC_USAGE.md](BACKGROUND_MUSIC_USAGE.md) for detailed instructions.

## How It Works

### Prerequisite Management (PrereqManager.ps1)

On first run, `PrereqManager.ps1` automatically:

1. **Checks FFmpeg**: Downloads from GitHub if missing or >30 days old
2. **Checks Python**: Installs Python 3.13 via winget if not found
3. **Checks Python packages**: Installs missing packages via pip
4. **Returns status**: Reports success/failure for each component

All checks run silently in the background when you launch the GUI.

### Speech Extraction Pipeline (SpeechSegmentExtractor.ps1)

1. **Extract Audio**: FFmpeg extracts audio from video
2. **Voice Activity Detection (VAD)**: Silero VAD detects speech segments
   - Filters out vario beeping (paragliding variometer)
   - Ignores wind noise and background sounds
3. **Whisper Transcription**: OpenAI Whisper transcribes detected segments
   - Swiss German → German transcription
   - GPU acceleration via PyTorch CUDA
4. **Segment Extraction**: Creates video clips for each speech segment
5. **Concatenation**: Combines all segments into final video

### Video Processing (VideoSummaryCreator.ps1)

- **GPU Detection**: Automatically uses NVIDIA NVENC if available
- **Smart Encoding**: Falls back to CPU encoding if no GPU
- **Efficient Processing**: Uses FFmpeg filter chains for fast processing
- **Quality Preservation**: Maintains original video quality

## File Structure

```
PS_VidAggregator/
├── GUI.ps1                     # Main application entry point
├── PrereqManager.ps1           # Automatic prerequisite installer
├── VideoSummaryCreator.ps1     # Core video processing logic
├── SpeechSegmentExtractor.ps1  # Whisper AI + VAD speech extraction
├── VideoConcatenator.ps1       # Multi-file concatenation
├── AddMusicToVideo.ps1         # Background music mixer
├── lib.ps1                     # Windows Forms helper functions
├── archive/                    # JSON save files (auto-created)
│   └── {VideoName}.json        # Per-video highlight data
├── ffmpeg/                     # FFmpeg binaries (auto-downloaded)
└── resources/                  # User assets (music, images)
```

## Advanced Features

### GPU Acceleration

The tool automatically detects NVIDIA GPUs and uses:
- **h264_nvenc** codec for video encoding (10-20x faster than CPU)
- **CUDA acceleration** for Whisper AI transcription (5-10x faster than CPU)

No configuration needed - if you have an NVIDIA GPU, it will be used automatically.

### Archive System

All highlights are automatically saved to `archive/{VideoName}.json`:

```json
{
  "VideoFile": "D:\\Videos\\2023-04-02-FullFlight.mp4",
  "SummaryLength": "00:15:00",
  "SummaryName": "Awesome Flight",
  "Highlights": [
    {
      "StartTime": "00:05:30",
      "EndTime": "00:06:45",
      "Comment": "Great thermal"
    }
  ]
}
```

Edit these JSON files manually or reload them by selecting the same video again.

### Multiple Video Workflows

**Create Summary**: Manual highlights only → `VideoName_Summary.mp4`
**Summary & Speech**: Manual + auto-detected speech → `VideoName_Summary_WithSpeech.mp4`

Both workflows support:
- Custom summary length
- Background music
- Text overlays
- GPU acceleration

## Troubleshooting

### "Python not found" after installation

Python was installed but needs PATH update. **Solution**: Restart PowerShell and run `.\GUI.ps1` again.

### Speech extraction fails

1. Check console output for detailed error messages
2. Verify Python packages: `python -c "import whisper"`
3. Check GPU: `nvidia-smi` (optional, falls back to CPU)

### FFmpeg not working

The tool auto-downloads FFmpeg. If issues persist:
1. Delete the `ffmpeg/` folder
2. Restart the tool - it will re-download

### Slow processing

- **Enable GPU**: Install NVIDIA drivers and CUDA toolkit
- **Reduce video resolution**: Process smaller videos first
- **Use "Create Summary" instead**: Speech extraction is slower (requires AI processing)

## Technical Details

### System Requirements

- **OS**: Windows 10/11
- **PowerShell**: 5.1+ (NOT PowerShell Core 7)
- **RAM**: 8GB minimum, 16GB recommended for Whisper
- **Storage**: 2GB free (for FFmpeg + Python packages)
- **GPU** (optional): NVIDIA GPU with CUDA support

### Supported Formats

**Video Input**: MP4, AVI, MKV, MOV (anything FFmpeg supports)
**Audio Input**: MP3, WAV, M4A, AAC
**Video Output**: MP4 (H.264)

### Performance

Typical processing times (RTX 3060 GPU):
- **Video Summary** (10 highlights from 60-min video): ~2-3 minutes
- **Speech Extraction** (60-min video): ~5-7 minutes (Whisper AI)
- **Background Music Mixing**: ~1-2 minutes

CPU-only processing is 5-10x slower.

## Contributing

Contributions welcome! Areas for improvement:
- Support for other languages/dialects
- Additional audio/video effects
- Export presets for social media platforms
- Batch processing multiple videos

## License

Open Source - Free for anyone to use and modify

## Credits

Built with:
- [FFmpeg](https://ffmpeg.org/) - Video processing
- [OpenAI Whisper](https://github.com/openai/whisper) - Speech recognition
- [Silero VAD](https://github.com/snakers4/silero-vad) - Voice activity detection
- [PowerShell](https://github.com/PowerShell/PowerShell) - Automation framework

Created for paragliding video editing, applicable to any long-form video content.
