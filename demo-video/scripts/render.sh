#!/bin/sh
set -eu
mkdir -p out
# Keep the complete supplied take within the original 16-second window.
source_duration="$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 public/user-recording.mov)"
ffmpeg -y -v error -i public/user-recording.mov \
  -vf "crop=2360:1560:112:76,setpts=(PTS-STARTPTS)*16/$source_duration,fps=60,scale=1416:936:flags=lanczos,setsar=1" \
  -frames:v 960 -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -an -movflags +faststart public/user-take-16s.mp4
ffmpeg -y -v error -i public/user-take-16s.mp4 -vf 'select=eq(n\,959)' -frames:v 1 public/user-last-frame.png
./node_modules/.bin/remotion still Background out/background.png
./node_modules/.bin/remotion render Logo-Outro out/logo-outro.mp4 --codec=h264 --crf=19 --jpeg-quality=80 --concurrency=2
python3 - <<'PY'
from pathlib import Path
w,h,r=1416,936,18
mask=bytearray([255])*(w*h)
for y in range(r):
 for x in range(r):
  d=((x+.5-r)**2+(y+.5-r)**2)**.5
  a=int(max(0,min(1,r+.5-d))*255)
  for xx,yy in ((x,y),(w-1-x,y),(x,h-1-y),(w-1-x,h-1-y)):mask[yy*w+xx]=a
Path('out/window-mask.pgm').write_bytes(('P5\n%d %d\n255\n'%(w,h)).encode()+mask)
PY
ffmpeg -y -v error -loop 1 -framerate 60 -i out/background.png -i public/user-take-16s.mp4 \
  -loop 1 -framerate 60 -i out/window-mask.pgm \
  -filter_complex '[1:v][2:v]alphamerge[window];[0:v][window]overlay=252:72:shortest=1,format=yuv420p[v]' \
  -map '[v]' -t 16 -r 60 -c:v libx264 -preset fast -crf 19 -an -video_track_timescale 90000 out/continuous-body.mp4
# Normalize the UI and Remotion segments before joining them. A stream-copy
# concat can change pixel format at the outro and reset downstream GIF filters.
ffmpeg -y -v error -i out/continuous-body.mp4 -i out/logo-outro.mp4 \
  -filter_complex '[0:v]scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,setsar=1[body];[1:v]scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,setsar=1[outro];[body][outro]concat=n=2:v=1:a=0[v]' \
  -map '[v]' -r 60 -frames:v 1200 -c:v libx264 -preset fast -crf 19 \
  -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -an -video_track_timescale 90000 -movflags +faststart out/foundation-evals-demo-20s.mp4
ffmpeg -v error -i out/foundation-evals-demo-20s.mp4 -f null -
