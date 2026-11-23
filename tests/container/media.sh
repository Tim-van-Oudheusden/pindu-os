#!/usr/bin/env bash
# Issue #54: GTK plays the launcher's VP9 background through GStreamer, which decodes it on
# the GPU where the GPU can and in software everywhere else. A container has no GPU, so this
# checks that the VA plug-in and the AMD and Intel VA drivers are there and load, and that a
# VP9 WebM file still plays without them. Which decoder a real GPU gets is checked on hardware.
set -euo pipefail
# shellcheck source=tests/container/lib.sh
source /tests/lib.sh

check "GStreamer's VA plug-in loads" gst-inspect-1.0 va

# libraries_resolve FILE: the file exists and ldd finds every library it needs.
# shellcheck disable=SC2329  # called through check
libraries_resolve() {
    local libraries
    libraries=$(ldd "$1") && ! grep -q 'not found' <<<"${libraries}"
}

for driver in radeonsi iHD; do
    check "the ${driver} VA driver and its libraries are installed" \
        libraries_resolve "/usr/lib64/dri/${driver}_drv_video.so"
done

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
gst-launch-1.0 -q videotestsrc num-buffers=30 ! video/x-raw,width=320,height=180 ! vp9enc ! webmmux ! \
    filesink location="${work}/clip.webm" >/dev/null 2>&1
check "a VP9 WebM file plays without a GPU" \
    gst-launch-1.0 -q playbin uri="file://${work}/clip.webm" video-sink=fakesink audio-sink=fakesink

finish
