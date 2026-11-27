#!/bin/sh
# Joins the frames from tool/store_video_test.dart into App Store app previews.
# H.264 High@4.0, 30 fps, 886x1920, with a silent stereo AAC track.
set -e
for lang in ko en; do
  ffmpeg -y -loglevel error -framerate 30 -i "build/store/video/$lang/frame-%05d.png" \
    -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -shortest \
    -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -b:v 10M -maxrate 12M -bufsize 20M \
    -r 30 -c:a aac -b:a 256k -movflags +faststart \
    "build/store/app-store/preview-$lang-886x1920.mp4"
done
