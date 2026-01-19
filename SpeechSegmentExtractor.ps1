function Extract-SpeechSegments {
    <#
    .SYNOPSIS
    Extracts video segments containing spoken language using Whisper ASR
    
    .DESCRIPTION
    Uses FFmpeg with Whisper to detect speech timestamps and concatenates all segments with speech into a single video
    
    .PARAMETER SourceVideoPath
    Path to the source video file
    
    .PARAMETER MinSilenceGap
    Minimum gap in seconds between speech segments to keep them separate (default: 1.0)
    
    .PARAMETER WhisperModel
    Whisper model to use: tiny, base, small, medium, large (default: base)
    
    .PARAMETER Language
    Language code for speech detection (e.g., 'en', 'de', 'es'). Auto-detect if not specified.
    
    .OUTPUTS
    Returns hashtable with success status, output path, and detected segments
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourceVideoPath,
        
        [Parameter(Mandatory=$false)]
        [double]$MinSilenceGap = 1.0,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('tiny', 'base', 'small', 'medium', 'large')]
        [string]$WhisperModel = 'base',
        
        [Parameter(Mandatory=$false)]
        [string]$Language = ''
    )
    
    begin {
        Write-Host "=== Speech Segment Extraction ===" -ForegroundColor Cyan
        Write-Host "Source: $SourceVideoPath" -ForegroundColor Gray
        Write-Host "Whisper Model: $WhisperModel" -ForegroundColor Gray
        
        # Validate input file
        if(!(Test-Path $SourceVideoPath)) {
            Write-Host "ERROR: Source video file not found: $SourceVideoPath" -ForegroundColor Red
            return @{
                Success = $false
                Error = "Source file not found"
            }
        }
        
        # Ensure FFmpeg is installed
        . "$PSScriptRoot\PrereqManager.ps1"
        try {
            $ffmpegPaths = Ensure-FFmpeg
            $ffmpeg = $ffmpegPaths.FFmpeg
            $ffprobe = $ffmpegPaths.FFprobe
        }
        catch {
            Write-Host "ERROR: Failed to initialize FFmpeg: $($_.Exception.Message)" -ForegroundColor Red
            return @{
                Success = $false
                Error = "FFmpeg initialization failed"
            }
        }
        
        # Check if Whisper is available (check for whisper or whisper.cpp)
        $whisperCmd = $null
        $whisperType = $null
        
        # Check for Python Whisper
        try {
            $pythonCheck = & python -c "import whisper; print('OK')" 2>&1
            if($pythonCheck -match 'OK') {
                $whisperCmd = 'python'
                $whisperType = 'python'
                Write-Host "Using Python Whisper" -ForegroundColor Green
                
                # Check GPU availability
                $gpuCheck = & python -c "import torch; print('CUDA' if torch.cuda.is_available() else 'CPU')" 2>&1
                if($gpuCheck -match 'CUDA') {
                    $gpuName = & python -c "import torch; print(torch.cuda.get_device_name(0))" 2>&1
                    Write-Host "GPU Detected: $gpuName" -ForegroundColor Green
                    Write-Host "CUDA Acceleration: ENABLED" -ForegroundColor Green
                }
                else {
                    Write-Host "WARNING: Running on CPU (No CUDA detected)" -ForegroundColor Yellow
                    Write-Host "To enable GPU acceleration, install PyTorch with CUDA:" -ForegroundColor Yellow
                    Write-Host "  pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118" -ForegroundColor Cyan
                    Write-Host "  (This will be MUCH faster for speech extraction)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "Python Whisper not found, checking for whisper.cpp..." -ForegroundColor Yellow
        }
        
        # Check for Silero VAD (Voice Activity Detection)
        $vadAvailable = $false
        try {
            $vadCheck = & python -c "import torch; import packaging; torch.hub.load(repo_or_dir='snakers4/silero-vad', model='silero_vad', force_reload=False); print('OK')" 2>&1
            if($vadCheck -match 'OK') {
                $vadAvailable = $true
                Write-Host "Voice Activity Detection (VAD): ENABLED" -ForegroundColor Green
                Write-Host "  (Will pre-filter vario beeping before transcription)" -ForegroundColor Gray
            }
        }
        catch {
            # Check if it's just a missing dependency
            $packagingCheck = & python -c "import packaging; print('OK')" 2>&1
            if($packagingCheck -notmatch 'OK') {
                Write-Host "Voice Activity Detection (VAD): DISABLED (missing dependency)" -ForegroundColor Yellow
                Write-Host "  To enable VAD for better vario filtering, run:" -ForegroundColor Gray
                Write-Host "  pip install packaging" -ForegroundColor Cyan
            }
            else {
                Write-Host "Voice Activity Detection (VAD): DISABLED" -ForegroundColor Yellow
                Write-Host "  To enable VAD for better vario filtering, run:" -ForegroundColor Gray
                Write-Host "  pip install torch" -ForegroundColor Cyan
            }
        }
        
        # Check for whisper.cpp
        if(!$whisperCmd) {
            try {
                $whisperCppPath = Get-Command "main.exe" -ErrorAction SilentlyContinue
                if($whisperCppPath) {
                    $whisperCmd = $whisperCppPath.Source
                    $whisperType = 'cpp'
                    Write-Host "Using whisper.cpp" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "whisper.cpp not found" -ForegroundColor Yellow
            }
        }
        
        if(!$whisperCmd) {
            Write-Host "`nERROR: Whisper not found. Please install one of the following:" -ForegroundColor Red
            Write-Host "  1. Python Whisper: pip install openai-whisper" -ForegroundColor Yellow
            Write-Host "  2. whisper.cpp: Download from https://github.com/ggerganov/whisper.cpp" -ForegroundColor Yellow
            return @{
                Success = $false
                Error = "Whisper not installed"
            }
        }
    }
    
    process {
        try {
            # Step 1: Extract audio from video
            Write-Host "\nStep 1: Extracting audio..." -ForegroundColor Cyan
            $tempAudio = Join-Path $env:TEMP "speech_extract_audio.wav"
            
            # Only normalize volume, don't filter frequencies (was removing speech)
            $audioFilters = "loudnorm"
            Write-Host "  Normalizing audio volume for better detection" -ForegroundColor Gray
            
            $ffmpegArgs = "-i `"$SourceVideoPath`" -vn -af `"$audioFilters`" -acodec pcm_s16le -ar 16000 -ac 1 `"$tempAudio`" -y"
            
            $audioProcess = Start-Process -FilePath $ffmpeg -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru
            if($audioProcess.ExitCode -ne 0) {
                throw "Failed to extract audio from video"
            }
            Write-Host "Audio extracted successfully" -ForegroundColor Green
            
            # Step 2: Run VAD to pre-filter audio (if available)
            $vadSegments = $null
            if($vadAvailable) {
                Write-Host "`nStep 2a: Running Voice Activity Detection..." -ForegroundColor Cyan
                Write-Host "  (Pre-filtering vario beeping and non-speech audio)" -ForegroundColor Gray
                
                $vadPythonScript = @"
import torch
import sys
from pprint import pprint

# Load Silero VAD model
model, utils = torch.hub.load(repo_or_dir='snakers4/silero-vad', model='silero_vad', force_reload=False)
(get_speech_timestamps, save_audio, read_audio, VADIterator, collect_chunks) = utils

# Windows-compatible audio loading
# Silero's read_audio uses sox which doesn't work on Windows, so we'll load manually
try:
    # Try using torchaudio with soundfile backend
    import torchaudio
    torchaudio.set_audio_backend("soundfile")  # Use soundfile backend on Windows
    wav, sr = torchaudio.load(r'$($tempAudio)')
    # Convert to mono if stereo
    if wav.shape[0] > 1:
        wav = wav.mean(dim=0, keepdim=True)
    wav = wav.squeeze()
    # Resample if needed
    if sr != 16000:
        resampler = torchaudio.transforms.Resample(sr, 16000)
        wav = resampler(wav)
    print(f'Loaded audio: {len(wav)} samples at 16kHz', flush=True)
except Exception as e:
    print(f'torchaudio failed: {e}', flush=True)
    print('Trying fallback method...', flush=True)
    # Fallback: load raw WAV with numpy/scipy
    try:
        import numpy as np
        from scipy.io import wavfile
        sr, wav = wavfile.read(r'$($tempAudio)')
        wav = wav.astype(np.float32) / 32768.0  # Convert to float32 [-1, 1]
        if len(wav.shape) > 1:  # Stereo to mono
            wav = wav.mean(axis=1)
        wav = torch.from_numpy(wav)
        if sr != 16000:
            # Simple resampling
            from scipy import signal
            wav_np = wav.numpy()
            num_samples = int(len(wav_np) * 16000 / sr)
            wav = torch.from_numpy(signal.resample(wav_np, num_samples))
        print(f'Loaded audio with fallback: {len(wav)} samples at 16kHz', flush=True)
    except Exception as e2:
        print(f'All audio loading methods failed: {e2}', flush=True)
        sys.exit(1)

# Get speech timestamps with aggressive filtering
# threshold: higher = more strict (0.5 is default, 0.7 is aggressive)
# min_speech_duration_ms: minimum speech length to consider (500ms)
# max_speech_duration_s: maximum continuous speech (30s)
# min_silence_duration_ms: minimum silence to split segments (300ms)
# speech_pad_ms: padding around speech (100ms)
print('Detecting voice activity...', flush=True)
speech_timestamps = get_speech_timestamps(
    wav, 
    model,
    threshold=0.6,  # Higher threshold = more strict (filters vario beeps better)
    sampling_rate=16000,
    min_speech_duration_ms=500,  # Minimum 500ms of speech
    max_speech_duration_s=30,  # Max 30s continuous
    min_silence_duration_ms=300,  # 300ms silence splits segments
    speech_pad_ms=100,  # 100ms padding
    return_seconds=True  # Return timestamps in seconds
)

print(f'Found {len(speech_timestamps)} voice segments', flush=True)

# Write timestamps to file
with open(r'$($env:TEMP)\vad_segments.txt', 'w') as f:
    for segment in speech_timestamps:
        start = segment['start']
        end = segment['end']
        f.write(f'{start:.3f},{end:.3f}\n')
        print(f'  Voice: {start:.2f}s - {end:.2f}s ({end-start:.1f}s)', flush=True)

print('Voice detection complete', flush=True)
"@
                $vadScriptPath = Join-Path $env:TEMP "vad_detect.py"
                Set-Content -Path $vadScriptPath -Value $vadPythonScript -Encoding UTF8
                
                $vadProcess = Start-Process -FilePath "python" -ArgumentList "`"$vadScriptPath`"" -NoNewWindow -Wait -PassThru
                
                if($vadProcess.ExitCode -eq 0) {
                    $vadSegmentsFile = Join-Path $env:TEMP "vad_segments.txt"
                    if(Test-Path $vadSegmentsFile) {
                        $vadSegments = Get-Content $vadSegmentsFile
                        Write-Host "Voice Activity Detection found $($vadSegments.Count) voice segments" -ForegroundColor Green
                        Write-Host "  (Only these segments will be transcribed, vario beeps filtered out)" -ForegroundColor Gray
                        
                        if($vadSegments.Count -eq 0) {
                            Write-Host "WARNING: No voice detected. Either no speech in video or VAD threshold too high." -ForegroundColor Yellow
                            Write-Host "  Falling back to full Whisper transcription..." -ForegroundColor Yellow
                            $vadSegments = $null
                        }
                    }
                }
                else {
                    Write-Host "WARNING: VAD failed, falling back to full Whisper transcription" -ForegroundColor Yellow
                }
            }
            
            # Step 2b: Run Whisper to get timestamps
            Write-Host "`nStep 2b: Running Whisper ASR..." -ForegroundColor Cyan
            $tempSrtFile = Join-Path $env:TEMP "speech_extract_subtitles.srt"
            
            if($whisperType -eq 'python') {
                # Create Python script for Whisper
                $vadSegmentsJson = if($vadSegments) {
                    # Convert VAD segments to JSON array for Python
                    $vadSegmentsArray = $vadSegments | ForEach-Object {
                        $parts = $_ -split ','
                        "[{0},{1}]" -f $parts[0], $parts[1]
                    }
                    "[{0}]" -f ($vadSegmentsArray -join ',')
                } else {
                    "None"
                }
                
                $pythonScript = @"
import whisper
import sys
import os
import json

# Add FFmpeg to PATH for Whisper
ffmpeg_dir = r'$($PSScriptRoot.Replace('\','\\'))\ffmpeg\bin'
if os.path.exists(ffmpeg_dir):
    os.environ['PATH'] = ffmpeg_dir + os.pathsep + os.environ.get('PATH', '')

model = whisper.load_model('$WhisperModel')
lang_param = '$Language' if '$Language' else None

# Initial prompt to help Whisper understand context and ignore vario beeping
initial_prompt = (
    "This is a paragliding flight video with Swiss German speech. "
    "Transcribe the Swiss German speech into standard German (Hochdeutsch). "
    "Transcribe only clear human speech and conversation. "
    "Ignore background sounds like vario beeping, wind noise, and aircraft sounds."
)

# VAD segments (if available)
vad_segments = $vadSegmentsJson

if vad_segments:
    print(f'VAD detected {len(vad_segments)} voice segments', flush=True)
    print('Transcribing full audio, then filtering to VAD segments...', flush=True)
    
    # Transcribe full audio (Whisper doesn't support segment clipping well)
    result = model.transcribe(
        r'$($tempAudio)',
        language=lang_param,
        verbose=True,
        fp16=True,
        temperature=0.0,
        condition_on_previous_text=False,
        initial_prompt=initial_prompt
    )
    
    # Filter segments to only those that overlap with VAD-detected voice
    print('Filtering transcription to VAD voice segments...', flush=True)
    all_segments = []
    for segment in result['segments']:
        seg_start = segment['start']
        seg_end = segment['end']
        
        # Check if this segment overlaps with any VAD segment
        for vad_start, vad_end in vad_segments:
            # Check for overlap
            if not (seg_end < vad_start or seg_start > vad_end):
                all_segments.append(segment)
                break  # Found overlap, include this segment
    
    print(f'Kept {len(all_segments)} segments that overlap with voice activity', flush=True)
else:
    print('Transcribing full audio (no VAD filtering)...', flush=True)
    result = model.transcribe(
        r'$($tempAudio)', 
        language=lang_param, 
        verbose=True,
        fp16=True,
        temperature=0.0,
        condition_on_previous_text=False,
        initial_prompt=initial_prompt
    )
    all_segments = result['segments']
    print(f'Transcription complete! Found {len(all_segments)} segments', flush=True)

# Write SRT format
with open(r'$($tempSrtFile.Replace('\','\\'))', 'w', encoding='utf-8') as f:
    segment_num = 1
    for segment in all_segments:
        start = segment['start']
        end = segment['end']
        text = segment['text'].strip()
        
        if not text:  # Skip empty segments
            continue
        
        # Format timestamps as SRT
        start_time = f"{int(start//3600):02d}:{int((start%3600)//60):02d}:{int(start%60):02d},{int((start%1)*1000):03d}"
        end_time = f"{int(end//3600):02d}:{int((end%3600)//60):02d}:{int(end%60):02d},{int((end%1)*1000):03d}"
        
        f.write(f"{segment_num}\n")
        f.write(f"{start_time} --> {end_time}\n")
        f.write(f"{text}\n\n")
        segment_num += 1

print('SRT file written successfully')
"@
                $pythonScriptPath = Join-Path $env:TEMP "whisper_transcribe.py"
                Set-Content -Path $pythonScriptPath -Value $pythonScript -Encoding UTF8
                
                Write-Host "Running Whisper transcription (this may take a few minutes)..." -ForegroundColor Yellow
                $whisperProcess = Start-Process -FilePath "python" -ArgumentList "`"$pythonScriptPath`"" -NoNewWindow -Wait -PassThru
                
                if($whisperProcess.ExitCode -ne 0) {
                    throw "Whisper transcription failed"
                }
            }
            else {
                # Use whisper.cpp
                $whisperArgs = "-m models/ggml-$WhisperModel.bin -f `"$tempAudio`" -osrt -of `"$($tempSrtFile.Replace('.srt',''))`""
                if($Language) {
                    $whisperArgs += " -l $Language"
                }
                
                Write-Host "Running Whisper transcription (this may take a few minutes)..." -ForegroundColor Yellow
                $whisperProcess = Start-Process -FilePath $whisperCmd -ArgumentList $whisperArgs -NoNewWindow -Wait -PassThru
                
                if($whisperProcess.ExitCode -ne 0) {
                    throw "Whisper transcription failed"
                }
            }
            
            Write-Host "Transcription complete" -ForegroundColor Green
            
            # Step 3: Parse SRT file to get timestamps
            Write-Host "`nStep 3: Parsing speech timestamps..." -ForegroundColor Cyan
            $speechSegments = Parse-SRTFile -SrtPath $tempSrtFile -MinSilenceGap $MinSilenceGap
            
            if($speechSegments.Count -eq 0) {
                Write-Host "WARNING: No speech detected in video" -ForegroundColor Yellow
                return @{
                    Success = $false
                    Error = "No speech detected"
                }
            }
            
            Write-Host "Found $($speechSegments.Count) speech segments" -ForegroundColor Green
            
            # Display segments
            $totalDuration = 0
            foreach($seg in $speechSegments) {
                $duration = $seg.End - $seg.Start
                $totalDuration += $duration
                Write-Host "  Segment: $([TimeSpan]::FromSeconds($seg.Start).ToString('hh\:mm\:ss\.fff')) - $([TimeSpan]::FromSeconds($seg.End).ToString('hh\:mm\:ss\.fff')) ($([Math]::Round($duration, 2))s)" -ForegroundColor Gray
            }
            Write-Host "Total speech duration: $([TimeSpan]::FromSeconds($totalDuration).ToString('hh\:mm\:ss\.fff'))" -ForegroundColor Cyan
            
            # Cleanup temp files
            Remove-Item $tempAudio -Force -ErrorAction SilentlyContinue
            Remove-Item $tempSrtFile -Force -ErrorAction SilentlyContinue
            if($whisperType -eq 'python') {
                Remove-Item $pythonScriptPath -Force -ErrorAction SilentlyContinue
            }
            
            Write-Host "`nSpeech extraction complete!" -ForegroundColor Green
            
            return @{
                Success = $true
                Segments = $speechSegments
                TotalDuration = $totalDuration
            }
        }
        catch {
            Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
            
            # Cleanup on error
            Remove-Item $tempAudio -Force -ErrorAction SilentlyContinue
            Remove-Item $tempSrtFile -Force -ErrorAction SilentlyContinue
            
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}

function Parse-SRTFile {
    <#
    .SYNOPSIS
    Parses SRT subtitle file and merges nearby segments (filters non-speech but doesn't store text)
    #>
    param(
        [string]$SrtPath,
        [double]$MinSilenceGap
    )
    
    if(!(Test-Path $SrtPath)) {
        Write-Host "ERROR: SRT file not found: $SrtPath" -ForegroundColor Red
        return @()
    }
    
    $srtContent = Get-Content $SrtPath -Raw -Encoding UTF8
    $segments = @()
    
    # Parse SRT format - need text to filter non-speech, but won't store it
    $pattern = '(?m)^\d+\r?\n(\d{2}):(\d{2}):(\d{2}),(\d{3}) --> (\d{2}):(\d{2}):(\d{2}),(\d{3})\r?\n(.+?)(?=\r?\n\r?\n|\z)'
    $matches = [regex]::Matches($srtContent, $pattern)
    
    foreach($match in $matches) {
        $startHours = [int]$match.Groups[1].Value
        $startMinutes = [int]$match.Groups[2].Value
        $startSeconds = [int]$match.Groups[3].Value
        $startMillis = [int]$match.Groups[4].Value
        
        $endHours = [int]$match.Groups[5].Value
        $endMinutes = [int]$match.Groups[6].Value
        $endSeconds = [int]$match.Groups[7].Value
        $endMillis = [int]$match.Groups[8].Value
        
        $startTime = $startHours * 3600 + $startMinutes * 60 + $startSeconds + $startMillis / 1000.0
        $endTime = $endHours * 3600 + $endMinutes * 60 + $endSeconds + $endMillis / 1000.0
        
        $text = $match.Groups[9].Value.Trim()
        
        # Filter out non-speech segments using text analysis
        if([string]::IsNullOrWhiteSpace($text)) { continue }
        if($text.Length -lt 3) { continue }
        if($text -match '^\[.*\]$') { continue }  # Skip [Music], [BLANK], etc.
        if($text -match '^[\.\,\!\?\-\s]+$') { continue }  # Skip only punctuation
        if($text -match '^[♪♫]+$') { continue }  # Skip music notes
        
        # Add segment with timestamps only (don't store text)
        $segments += @{
            Start = $startTime
            End = $endTime
        }
    }
    
    if($segments.Count -eq 0) {
        return @()
    }
    
    Write-Host "Found $($segments.Count) speech segments after filtering" -ForegroundColor Green
    
    # Merge segments that are close together
    $mergedSegments = @()
    $currentSegment = $segments[0]
    
    for($i = 1; $i -lt $segments.Count; $i++) {
        $gap = $segments[$i].Start - $currentSegment.End
        
        if($gap -le $MinSilenceGap) {
            # Merge with current segment
            $currentSegment.End = $segments[$i].End
        }
        else {
            # Save current segment and start new one
            $mergedSegments += $currentSegment
            $currentSegment = $segments[$i]
        }
    }
    
    # Add last segment
    $mergedSegments += $currentSegment
    
    Write-Host "Merged into $($mergedSegments.Count) segments (gaps > ${MinSilenceGap}s)" -ForegroundColor Cyan
    
    return $mergedSegments
}

function Build-ConcatFilter {
    <#
    .SYNOPSIS
    Builds FFmpeg filter_complex string for concatenating video segments
    #>
    param(
        [array]$Segments
    )
    
    $videoFilters = @()
    $audioFilters = @()
    $concatInputs = @()
    
    for($i = 0; $i -lt $Segments.Count; $i++) {
        $start = $Segments[$i].Start
        $duration = $Segments[$i].End - $start
        
        # Video trim
        $videoFilters += "[0:v]trim=start=$start`:duration=$duration,setpts=PTS-STARTPTS[v$i]"
        
        # Audio trim
        $audioFilters += "[0:a]atrim=start=$start`:duration=$duration,asetpts=PTS-STARTPTS[a$i]"
        
        # Add to concat inputs
        $concatInputs += "[v$i][a$i]"
    }
    
    # Combine all filters
    $allFilters = $videoFilters + $audioFilters
    
    # Build concat filter
    $concatFilter = ($concatInputs -join '') + "concat=n=$($Segments.Count):v=1:a=1[outv][outa]"
    
    # Combine everything
    $filterComplex = ($allFilters -join ';') + ';' + $concatFilter
    
    return $filterComplex
}
