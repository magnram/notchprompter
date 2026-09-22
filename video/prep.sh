#!/bin/sh
# Rebuilds every derived media file from the take in source/, using the offsets in timings.json.
# Inputs are read only. Run from anywhere:  sh prep.sh
set -e
cd "$(dirname "$0")"
J() { node -e "const t=require('./timings.json');console.log(t.source.$1)"; }
CAM=$(J camera); SCR=$(J screen); IN=$(J voiceIn); OUT=$(J voiceOut); LEAD=$(J screenLead); CROP=$(J panelCrop)
LEN=$(node -e "console.log(($OUT-$IN).toFixed(3))")
# the camera's audio stream starts later than its video (0.144 s on 12.09.41); voice-full.wav starts at the
# first audio sample, so shift the voice trim by that amount to keep lips and voice in sync
ALEAD=$(ffprobe -v error -select_streams a:0 -show_entries stream=start_time -of csv=p=0 "$CAM")
A_IN=$(node -e "console.log(($IN-$ALEAD).toFixed(3))"); A_OUT=$(node -e "console.log(($OUT-$ALEAD).toFixed(3))")
SCR_IN=$(node -e "console.log(($IN+$LEAD).toFixed(3))")

# 1. voice: denoise, compress, normalise to about -16 LUFS (camera timeline), then trim to the video timeline
ffmpeg -v error -y -i "$CAM" -vn -ac 1 -ar 48000 \
  -af "highpass=f=80,afftdn=nf=-45:nr=10,acompressor=threshold=-34dB:ratio=3.5:attack=8:release=150:makeup=1,volume=24.2dB,alimiter=limit=0.84:attack=3:release=60:level=false" \
  -c:a pcm_s24le audio/voice-full.wav
# stereo: ffmpeg upmixes mono at -3 dB per channel, so the stereo mix measures about -16 LUFS
ffmpeg -v error -y -ss "$A_IN" -to "$A_OUT" -i audio/voice-full.wav -ac 2 \
  -af "afade=t=in:d=0.08,afade=t=out:st=$(node -e "console.log(($LEN-0.2).toFixed(3))"):d=0.2" -c:a pcm_s24le audio/voiceover.wav

# 2. camera at constant 30 fps, trimmed to the video timeline
ffmpeg -v error -y -i "$CAM" -an -vf fps=30 -c:v libx264 -crf 12 -preset slow -pix_fmt yuv420p source/cam30.mp4
ffmpeg -v error -y -ss "$IN" -i source/cam30.mp4 -t "$LEN" -an -c:v libx264 -crf 12 -preset slow -pix_fmt yuv420p source/cam-vt.mp4

# 3. presenter cut-out: Apple Vision person segmentation (.accurate), temporal smoothing, feathered edge, VP9 alpha
[ -x tools/segment ] || swiftc -O tools/segment.swift -o tools/segment
./tools/segment source/cam-vt.mp4 1920 1080 0.55 2> tools/segment.log | \
  ffmpeg -v error -y -i source/cam-vt.mp4 -f rawvideo -pix_fmt gray -s 1920x1080 -r 30 -i - \
  -filter_complex "[1:v]erosion,gblur=sigma=2.2,format=gray[m];[0:v]format=yuva420p[c];[c][m]alphamerge,format=yuva420p[o]" \
  -map "[o]" -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 22 -row-mt 1 -deadline good -cpu-used 2 -auto-alt-ref 0 assets/presenter.webm

# 4. real prompter footage: crop the panel out of the screen recording, 2x lanczos, 30 fps
ffmpeg -v error -y -ss "$SCR_IN" -i "$SCR" -t "$LEN" -an \
  -vf "crop=$CROP,fps=30,scale=1324:684:flags=lanczos,format=yuv420p" \
  -c:v libx264 -crf 14 -preset slow -g 30 -movflags +faststart assets/prompter-live.mp4

node retime.mjs
