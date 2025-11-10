#!/bin/bash

set -e

MODE="$1"
ARG_1="$2"
ARG_2="${3:-0}"

usage() {
    echo "Usage:"
    echo "  $0 -d <seconds>             # Delay out.mp4 by x seconds"
    echo "  $0 -t <input_1> <input_2>   # adjusts input audio for fps difference"
    echo "                              # input_1 is the file with the correct audio"
    echo "                              # input_2 is the file with the correct video"
    exit 1
}

get_fps() {
    local file="$1"
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 "$file"
}

float_fps() {
    echo "$1" | awk -F'/' '{ if (NF==2) printf "%.6f", $1/$2; else printf "%.6f", $1 }'
}

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    usage
    exit 1
fi

case "$MODE" in
    -d)
        echo "Set delay of $ARG seconds."
        if [ ! -f out.mp4 ]; then
            echo "Erro: out.mp4 was not found!"
            exit 1
        fi
        ffmpeg -y -i out.mp4 -itsoffset "$ARG_1" -i out.mp4 -map 0:v -map 1:a -c copy delayed.mp4
        ;;

    -t)
        FPS_1=$(get_fps "$ARG_1")
        FPS_2=$(get_fps "$ARG_2")
        ATEMPO=$(awk -v f1="$(float_fps $FPS_2)" -v f2="$(float_fps $FPS_1)" 'BEGIN { printf "%.6f", f1/f2 }')

        echo "1: 	    $FPS_1"
        echo "2: 	    $FPS_2"
        echo "Tempo: 	$ATEMPO"

        ffmpeg -i "$ARG_1" -acodec copy -vn audio.aac
        if [ $ATEMPO -eq 1.0 ]; then
            echo "No FPS adjustment necessary."
            ffmpeg -i "$ARG_2" -i "audio.aac" -map 0:v -map 1:a -c:v copy -c:a copy out.mp4
        else
            echo "FPS adjustment of $ATEMPO is necessary."
            ffmpeg -i audio.aac -filter:a "atempo=$ATEMPO" -c:a aac -b:a 192k audio_fixed.aac
            ffmpeg -i "$ARG_2" -i "audio_fixed.aac" -map 0:v -map 1:a -c:v copy -c:a copy out.mp4
        fi
	    ;;

    *)
        usage
        ;;
esac