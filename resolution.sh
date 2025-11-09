#!/bin/bash

FOLDER="$1"
FILES=( "$FOLDER"/* )
EXTS=("mp4" "mkv" "mov" "avi" "flv" "webm")

usage() {
    echo "Usage:"
    echo "  $0 <folder_path>             # prints resolution count of all videos in the given folder"
    exit 1
}

if [ $# -lt 2 ] || [ $# -gt 2 ]; then
    usage
    exit 1
fi

for file in "${FILES[@]}"; do

    ext="${file##*.}"
    ext="${ext,,}"

    is_video=false
    for e in "${EXTS[@]}"; do
        if [[ "$ext" == "$e" ]]; then
            is_video=true
            break
        fi
    done

    if [[ "$is_video" == true ]]; then
	    echo "$file"
        ffprobe -v 0 -hide_banner -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file"
    fi
done