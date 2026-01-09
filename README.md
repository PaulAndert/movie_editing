# Movie Editing Scripts
Collection of Bash scripts for automating video/audio editing tasks using FFmpeg.  

## Requirements
- FFmpeg (https://ffmpeg.org/)
- Bash

## Scripts
### edit_movie.sh
Combine the audio stream from one video file with the video stream from another, handling:

- Automatic FPS adjustment between videos
- Optional audio delay (forward/backward)
- Merging multiple audio streams into one final video
- Print info about video/audio files

**Usage examples:**
```bash
# Adjust FPS differences between German and English versions
./edit_movie.sh -t mov.ger.mp4 mov.eng.mp4

# Delay audio by 2 seconds
./edit_movie.sh -d 2

# Create final MKV with multiple audio streams
./edit_movie.sh -f mov_fixed.ger.mp4 mov.eng.mp4

# Print info of a video/audio file
./edit_movie.sh -i mov.mp4
```

**Scenario:**  
Use these scripts to merge different movie versions (e.g., low-res German + high-res English), adjust FPS, synchronize audio/video, and produce a final MKV with multiple audio streams.

### fps.sh
Print the FPS of all video files in a folder:
```bash
./fps.sh /path/to/videos
```
  
### resolution.sh
Print the resolution of all video files in a folder:
```bash
./resolution.sh /path/to/videos
```

