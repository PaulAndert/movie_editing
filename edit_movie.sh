#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="$SCRIPT_DIR/iso639-2.csv"

MODE="$1"
ARG_1="$2"
ARG_2="${3:-0}"

usage() {
    echo "Usage:"
    echo "  em -d <seconds>             # Delay out.mp4 by x seconds"
    echo "  em -t <input_1> <input_2>   # adjusts input audio for fps difference"
    echo "  em -f <input_1> <input_2>   # create final mkv with multiple audio streams"
    echo "  em -i <input_1>             # print infos to file"
    echo ""
    echo "                              # input_1 is the file with the correkt audio"
    echo "                              # input_2 is the file with the correct video"
    echo ""
    echo "Example usage:"
    echo "download a version of a movie in german with low resolution and one in english with a better one"
    echo "then rename the files correctly like for example 'name (year) resolution.lan.ext'"
    echo "then use em -t ger eng to adjust possible fps differences"
    echo "then use em -d s to adjust possible movie starttimes in the new combined version"
    echo "then use em -f new_ger eng to create the final file"
    exit 1
}

get_fps_from_name() {
    local file="$1"
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 "$file"
}

get_float_from_fps() {
    echo "$1" | awk -F'/' '{ if (NF==2) printf "%.6f", $1/$2; else printf "%.6f", $1 }'
}

get_code_from_name() {
    local file="$1"

    if [[ "$file" =~ ^(.+)\.([a-z]{3})\.([^.]+)$ ]]; then
        BASE="${BASH_REMATCH[1]}"
        CODE="${BASH_REMATCH[2]}"
        EXT="${BASH_REMATCH[3]}"
    else
        echo "Error: filename '$file' is in the wrong format."
        exit 1
    fi

    # is code 3 chars
    if [[ ${CODE} != ??? ]]; then
        echo "Error: ISO-code '$CODE' is not 3 chars long."
    fi
    echo "$CODE"
}

get_value_from_code() {
    local code="$1"

    # try loading the value for this code
    VALUE=$(awk -F',' -v code="$code" '$1==code {print $2}' "$CSV_FILE")
    if [[ -z "$VALUE" ]]; then
        echo "Error: code '$code' can't be found."
    fi
    echo "$VALUE"
}

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    usage
    exit 1
fi

case "$MODE" in
    -d)
        if [ ! -f out.mp4 ]; then
            echo "Erro: out.mp4 was not found!"
            exit 1
        fi
        echo "Set delay of $ARG seconds:"
        ffmpeg -y -i out.mp4 -itsoffset "$ARG_1" -i out.mp4 -map 0:v -map 1:a -c copy delayed.mp4
        ;;

    -t)
        FPS_1=$(get_fps_from_name "$ARG_1")
        FPS_2=$(get_fps_from_name "$ARG_2")
        ATEMPO=$(awk -v f1="$(get_float_from_fps $FPS_2)" -v f2="$(get_float_from_fps $FPS_1)" 'BEGIN { printf "%.6f", f1/f2 }')

        echo "1: 	    $FPS_1"
        echo "2: 	    $FPS_2"
        echo "Tempo: 	$ATEMPO"

        read -p "Continiue? [Y/n] (s for skipping fps adjustment) " input
        if [[ "$input" == "n" || "$input" == "N" ]]; then
            echo "exiting."
            exit 1
        fi

        if [ "$ATEMPO" = "1.000000" || "$input" == "s" || "$input" == "S" || "$input" == "skip" ]; then
            echo "extracting audio:"
            ffmpeg -hide_banner -loglevel error -stats -i "$ARG_1" -acodec copy -vn audio.aac
            echo "rebuild new file:"
            ffmpeg -hide_banner -loglevel error -stats -i "$ARG_2" -i "audio.aac" -map 0:v -map 1:a -c:v copy -c:a copy out.mp4
        else
            echo "extracting audio:"
            ffmpeg -hide_banner -loglevel error -stats -i "$ARG_1" -acodec copy -vn audio.aac
            echo "adjust audio to fit video from input 2:"
            ffmpeg -hide_banner -loglevel error -stats -i audio.aac -filter:a "atempo=$ATEMPO" -c:a aac -b:a 192k audio_fixed.aac
            echo "rebuild new file:"
            ffmpeg -hide_banner -loglevel error -stats -i "$ARG_2" -i "audio_fixed.aac" -map 0:v -map 1:a -c:v copy -c:a copy out.mp4
        fi
	    ;;
    -f)
        echo "start creating final file:"

        CODE_1=$(get_code_from_name "$ARG_1")
        if [[ "$CODE_1" == *'Error'* ]]; then
            echo "$CODE_1"
            exit 1
        fi
        VALUE_1=$(get_value_from_code "$CODE_1")
        if [[ "$VALUE_1" == *'Error'* ]]; then
            echo "$VALUE_1"
            exit 1
        fi

        SKIP_LANG_2=false
        CODE_2=$(get_code_from_name "$ARG_2")
        if [[ "$CODE_2" == *'Error'* ]]; then
            echo "$CODE_2"
            SKIP_LANG_2=true
        else
            VALUE_2=$(get_value_from_code "$CODE_2")
            if [[ "$VALUE_2" == *'Error'* ]]; then
                echo "$VALUE_2"
                SKIP_LANG_2=true
            fi
        fi

        VIDEO_START=$(ffprobe -v error -select_streams v:0 -show_entries stream=start_time -of csv=p=0 "$ARG_1")
        AUDIO_START=$(ffprobe -v error -select_streams a:0 -show_entries stream=start_time -of csv=p=0 "$ARG_1")
        DIFFERENCE=$(echo "$AUDIO_START - $VIDEO_START" | bc)
        
        # TODO entscheiden ob video eine rolle spielt, falls ja dann muss lösung egfunden werden für negative audio verschiebung
        MILI_SEC=$(awk "BEGIN {printf \"%d\", $AUDIO_START*1000}")

        echo "INFO:"
        echo "File 1:           $CODE_1   $VALUE_1"
        if $SKIP_LANG_2; then
            echo "Warning: skipped Language 2 ($CODE_2)"
        else
            echo "File 2:           $CODE_2   $VALUE_2"
        fi
        
        LAYOUT=$(ffprobe -v error -select_streams a:0 -show_entries stream=channel_layout -of default=nw=1:nk=1 "$ARG_1")
        CHANNEL=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$ARG_1")
        if [[ "$LAYOUT" == "unknown" ]]; then
            case $CHANNEL in
                1) LAYOUT=mono ;;
                2) LAYOUT=stereo ;;
                6) LAYOUT=5.1 ;;
                8) LAYOUT=7.1 ;;
                *) LAYOUT=stereo ;; # fallback
            esac
        fi

        echo ""
        echo "Layout File 1:    $CHANNEL -> $LAYOUT"
        echo "Diff File 2:      $DIFFERENCE -> $MILI_SEC"
        echo ""

        # ,asetpts=PTS-STARTPTS
        # FILTER_COMPLEX="[0:a:0]aformat=sample_fmts=fltp:channel_layouts=$LAYOUT,adelay=${MILI_SEC}[aud_de]"
        FILTER_COMPLEX="[0:a:0]aformat=sample_fmts=fltp,aresample=async=1:first_pts=0,adelay=${MILI_SEC}|${MILI_SEC}[aud_de]"

        read -p "Continue? [Y/n] " input
        if [[ "$input" == "n" || "$input" == "N" ]]; then
            echo "exiting."
            exit 1
        fi

        
        if $SKIP_LANG_2; then
            OUTFILE="${ARG_2%.*.*}.$CODE_1.TODO.mkv"
            ffmpeg -err_detect ignore_err -hide_banner -loglevel error -stats -i "$ARG_1" -i "$ARG_2" \
                -movflags +faststart \
                -filter_complex "$FILTER_COMPLEX" \
                -map 1:v \
                -map "[aud_de]" \
                -map 1:a? \
                -map 1:s:m:codec:subrip? \
                -c:v copy \
                -c:a:0 aac -b:a:0 192k \
                -c:s srt \
                -disposition:a:0 default \
                -metadata:s:a:0 language="$CODE_1" \
                -metadata:s:a:0 title="$VALUE_1" \
                "$OUTFILE"

        else
            OUTFILE="${ARG_2%.*.*}.$CODE_1.$CODE_2.mkv"
            ffmpeg -err_detect ignore_err -hide_banner -loglevel error -stats -i "$ARG_1" -i "$ARG_2" \
                -movflags +faststart \
                -filter_complex "$FILTER_COMPLEX" \
                -map 1:v \
                -map "[aud_de]" \
                -map 1:a? \
                -map 1:s:m:codec:subrip? \
                -c:v copy \
                -c:a:0 aac -b:a:0 192k \
                -c:s srt \
                -disposition:a:0 default \
                -metadata:s:a:0 language="$CODE_1" \
                -metadata:s:a:0 title="$VALUE_1" \
                -metadata:s:a:1 language="$CODE_2" \
                -metadata:s:a:1 title="$VALUE_2" \
                "$OUTFILE"
        fi

        ;;
    -i)
        echo "### File Infos ###"
        echo "Video:"

        RESOLUTION=$(ffprobe -v 0 -hide_banner -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$ARG_1")
        echo "  Resolution:           $RESOLUTION"

        FPS=$(get_fps_from_name "$ARG_1")
        echo "  Framerate:            $FPS"

        VIDEO_START=$(ffprobe -v error -select_streams v:0 -show_entries stream=start_time -of csv=p=0 "$ARG_1")
        echo "  Video start:          $VIDEO_START"

        echo ""
        echo "Audio:"

        INDEX=0
        while IFS= read -r line; do
            echo "  Audio Track:          $INDEX"
            LAYOUT=$(ffprobe -v error -select_streams a:$INDEX -show_entries stream=channel_layout -of default=nw=1:nk=1 "$ARG_1")
            CHANNEL=$(ffprobe -v error -select_streams a:$INDEX -show_entries stream=channels -of csv=p=0 "$ARG_1")
            if [[ "$LAYOUT" == "unknown" ]]; then
                case $CHANNEL in
                    1) LAYOUT=mono ;;
                    2) LAYOUT=stereo ;;
                    6) LAYOUT=5.1 ;;
                    8) LAYOUT=7.1 ;;
                    *) LAYOUT=stereo ;; # fallback
                esac
            fi

            echo "  Layout:               $CHANNEL -> $LAYOUT"

            AUDIO_START=$(ffprobe -v error -select_streams a:$INDEX -show_entries stream=start_time -of csv=p=0 "$ARG_1")
            echo "  Audio start:          $AUDIO_START"

            LANGUAGE=$(ffprobe -v error -select_streams a:$INDEX -show_entries stream_tags=language -of default=nw=1:nk=1 "$ARG_1")
            TITLE=$(ffprobe -v error -select_streams a:$INDEX -show_entries stream_tags=title -of default=nw=1:nk=1 "$ARG_1")
            echo "  Language:             $LANGUAGE"
            echo "  Title:                $TITLE"

            VALUE=$(get_value_from_code "$LANGUAGE")
            echo "  Language Match:       $VALUE"

            ((INDEX=INDEX+1))
            echo ""
        done < <(ffprobe -v error -select_streams a -show_entries stream=codec_name,channels -of csv=p=0 "$ARG_1")

        ;;
    *)
        usage
        ;;
esac