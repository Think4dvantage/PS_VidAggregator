# Automated Prerequisite Installation

## Overview

Starting from this version, PS_VidAggregator automatically installs all required prerequisites when you first run the application. No manual installation needed!

## What Gets Installed Automatically

### 1. FFmpeg (Video Processing)
- **Source**: GitHub (BtbN/FFmpeg-Builds - latest release)
- **Version**: Master build with CUDA/NVENC support
- **Location**: `.\ffmpeg\` folder in the script directory
- **Updates**: Checks for updates every 30 days

### 2. Python 3.13 (AI Processing)
- **Source**: winget (Python.Python.3.13)
- **Installation Method**: Silent install via Windows Package Manager
- **Location**: System-wide installation (added to PATH)
- **Note**: May require PowerShell restart after first install

### 3. Python Packages (via pip)

The following packages are automatically installed:

| Package | Purpose | Special Notes |
|---------|---------|---------------|
| **openai-whisper** | AI speech recognition | Auto-detects Swiss German |
| **torch** | Deep learning framework | Installed with CUDA cu118 support |
| **torchaudio** | Audio processing for PyTorch | Bundled with torch |
| **soundfile** | Audio file I/O | Windows-compatible backend |
| **scipy** | Scientific computing | Used for audio fallback |
| **packaging** | Version management | Dependency tracking |

## How It Works

### On First Run

When you launch `GUI.ps1`, the script:

1. **Loads PrereqManager.ps1**
2. **Runs Ensure-Prerequisites function**
3. **Shows progress in console**:
   ```
   === Checking FFmpeg ===
   FFmpeg not found, will download...
   Downloading from GitHub...
   FFmpeg installed successfully!
   FFmpeg: OK
   
   === Checking Python ===
   Python not found
   Attempting to install Python via winget...
   Python installed successfully!
   Python: OK
   
   === Checking Python Packages ===
   Installing openai-whisper...
   Installing torch (with GPU support)...
   Installing soundfile...
   All Python packages: OK
   ```

4. **Continues to GUI** (or prompts restart if needed)

### On Subsequent Runs

The script quickly checks:
- ✅ FFmpeg present and up-to-date
- ✅ Python available in PATH
- ✅ All packages importable

If everything is OK, the GUI launches immediately (< 1 second).

## Installation Locations

### FFmpeg
```
PS_VidAggregator/
└── ffmpeg/
    ├── bin/
    │   ├── ffmpeg.exe
    │   └── ffprobe.exe
    ├── .version.txt  (tracks download date)
    └── ...
```

### Python (via winget)
```
C:\Users\{YourUser}\AppData\Local\Programs\Python\Python313\
├── python.exe
├── Scripts\
│   └── pip.exe
└── Lib\
    └── site-packages\
```

### Python Packages (via pip)
```
C:\Users\{YourUser}\AppData\Local\Programs\Python\Python313\Lib\site-packages\
├── whisper\
├── torch\
├── soundfile\
├── scipy\
└── packaging\
```

## Manual Installation (If Needed)

If automatic installation fails, you can install manually:

### FFmpeg
```powershell
# Delete the ffmpeg folder and restart GUI.ps1
Remove-Item -Path ".\ffmpeg" -Recurse -Force
.\GUI.ps1  # Will auto-download FFmpeg
```

### Python
```powershell
# Via winget (recommended)
winget install -e --id Python.Python.3.13

# Or download from python.org
# https://www.python.org/downloads/
# Make sure to check "Add Python to PATH"
```

### Python Packages
```powershell
# Install all at once
pip install openai-whisper soundfile scipy packaging

# PyTorch with CUDA (for GPU acceleration)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

## Troubleshooting

### "Python not found" after auto-install

**Cause**: Python was installed but PATH wasn't updated in current session

**Solution**: 
```powershell
# Restart PowerShell, then run:
.\GUI.ps1
```

### "pip: command not found"

**Cause**: Python installed but pip not in PATH

**Solution**:
```powershell
# Use python -m pip instead
python -m pip install openai-whisper

# Or find pip manually
C:\Users\{YourUser}\AppData\Local\Programs\Python\Python313\Scripts\pip.exe install openai-whisper
```

### Slow package installation

**Normal behavior**: PyTorch with CUDA is ~2.5GB and takes 5-10 minutes to download

**Progress check**:
```powershell
# You'll see output like:
# Downloading torch-2.1.0+cu118-cp313-cp313-win_amd64.whl (2.5 GB)
# This is normal, just wait for completion
```

### GPU not detected

**Check NVIDIA drivers**:
```powershell
nvidia-smi  # Should show GPU info
```

**If nvidia-smi fails**: Install/update NVIDIA drivers from [nvidia.com](https://www.nvidia.com/Download/index.aspx)

**Fallback**: The tool will use CPU encoding automatically (slower but works)

### winget not available

**Cause**: Windows 10 before version 1809, or Windows Package Manager not installed

**Solution**: Install Python manually from [python.org](https://www.python.org/downloads/), then restart GUI.ps1

## Technical Details

### PrereqManager.ps1 Functions

| Function | Purpose | Silent Mode |
|----------|---------|-------------|
| **Ensure-Prerequisites** | Orchestrates all checks | ❌ Shows progress |
| **Ensure-FFmpeg** | Downloads/updates FFmpeg | ✅ Optional |
| **Ensure-Python** | Installs Python via winget | ✅ Optional |
| **Ensure-PythonPackages** | Installs pip packages | ✅ Optional |

### Version Tracking

**FFmpeg**: Stored in `ffmpeg\.version.txt`
```json
{
  "DownloadDate": "2026-01-16T10:30:00",
  "Source": "https://github.com/..."
}
```

**Python Packages**: Checked via import test
```powershell
python -c "import whisper"  # Returns 0 if OK
```

### Update Logic

**FFmpeg**:
- Checks download date every run
- If > 30 days old: checks GitHub for newer release
- Only updates if newer version exists
- Preserves existing installation if up-to-date

**Python**:
- winget handles updates via Windows Update
- Manual update: `winget upgrade Python.Python.3.13`

**Python Packages**:
- No auto-update (stability reasons)
- Manual update: `pip install --upgrade openai-whisper torch`

## Benefits of Auto-Installation

✅ **Zero manual setup** - Just run the GUI  
✅ **Consistent environment** - Everyone gets the same versions  
✅ **Easy deployment** - Share the folder, it just works  
✅ **Auto-updates** - FFmpeg stays current automatically  
✅ **Fallback handling** - CPU encoding if no GPU  
✅ **Error recovery** - Detailed error messages if issues occur  

## Performance Notes

### First Run Timing
- **FFmpeg download**: ~30 seconds (200MB)
- **Python install**: ~2 minutes (Windows Package Manager)
- **Pip packages**: ~5-10 minutes (PyTorch is 2.5GB)
- **Total first run**: ~10-15 minutes

### Subsequent Runs
- **Prerequisite check**: < 1 second
- **GUI launch**: Immediate

## Compatibility

### Operating Systems
- ✅ Windows 10 (1809 or later)
- ✅ Windows 11
- ❌ Linux/macOS (PowerShell Windows Forms not supported)

### PowerShell Versions
- ✅ PowerShell 5.1 (Windows default)
- ✅ PowerShell 6.x
- ❌ PowerShell 7+ (Windows Forms compatibility issues)

### Python Versions
- ✅ Python 3.13 (auto-installed)
- ✅ Python 3.10-3.12 (if manually installed)
- ❌ Python 2.x (not supported)
- ❌ Python 3.9 or older (Whisper requires 3.10+)

## Future Enhancements

Planned improvements:
- [ ] Progress bar for package downloads
- [ ] Retry logic for failed downloads
- [ ] Offline installation support
- [ ] Custom Python package mirrors
- [ ] CUDA toolkit auto-installation

## Questions?

If you encounter issues with automatic installation:

1. **Check console output** - Detailed error messages are shown
2. **Try manual installation** - See "Manual Installation" section above
3. **Check system logs** - Windows Event Viewer for winget errors
4. **Report issues** - Include console output when reporting bugs

The tool is designed to work out-of-the-box, but manual installation is always an option if auto-install fails.
