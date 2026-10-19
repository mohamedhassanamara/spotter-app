#!/bin/bash
# Answers the integration tests' `deviceShot` requests with real simulator screenshots.
#   tool/device_shots.sh <simulator-id> <folder>   (run in the background, then run the test with
#   --dart-define=SHOTS_DIR=<folder>)
sim="$1"; dir="$2"; mkdir -p "$dir"
while true; do
  for f in "$dir"/.req-*; do
    [ -e "$f" ] || continue
    name="${f##*/.req-}"
    xcrun simctl io "$sim" screenshot "$dir/$name.png" >/dev/null 2>&1
    rm -f "$f"
  done
  sleep 0.1
done
