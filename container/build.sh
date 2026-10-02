#!/usr/bin/env bash
# Builds a podman image of glasnost.
#
# `bjo publish` puts glasnost and everything it loads into container/app, with
# paths relative to the program, so the image only needs that directory and the
# .NET runtime. `--whole-stdlib` copies the whole standard library, sources and
# documentation included, because samizdat's @defmodule reads module docs from
# it at run time.
#
#   container/build.sh [IMAGE-NAME]        (default: glasnost)
#
# bjo is found on PATH, or set BJO to its path.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
image=${1:-glasnost}
bjo=${BJO:-bjo}

command -v "$bjo" >/dev/null || {
  echo "build.sh: no bjo; put it on PATH, or set BJO to its path." >&2
  exit 1
}

(cd "$repo" && "$bjo" publish --whole-stdlib -o "$here/app")

# The directories the image needs, copied in by the Containerfile: the base
# image has no shell to make them with.
rm -rf "$here/skel"
mkdir -p "$here/skel/srv/glasnost/wwwroot" "$here/skel/cache" "$here/skel/site"

# Inside a toolbox or distrobox there is usually no podman, but the host has
# one and sees the same /home, so the published directory is where it expects
# it. The host's podman gets a clean environment: the toolbox's (container=podman
# and the rest) makes a rootless build fail to join its user namespace.
host_env=(env -i "HOME=$HOME" "USER=$USER" "PATH=/usr/bin:/bin"
          "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}")
# A podman inside the toolbox is not used even when there is one: rootless
# podman nested in a rootless container cannot make its user namespace.
if [ -e /run/.containerenv ] && command -v host-spawn >/dev/null; then
  podman=(host-spawn "${host_env[@]}" podman)
elif [ -e /run/.containerenv ] && command -v distrobox-host-exec >/dev/null; then
  podman=(distrobox-host-exec "${host_env[@]}" podman)
elif [ -e /run/.containerenv ] && command -v flatpak-spawn >/dev/null; then
  podman=(flatpak-spawn --host "${host_env[@]}" podman)
elif command -v podman >/dev/null; then
  podman=(podman)
else
  echo "build.sh: no podman here; on a machine that has one, build with"
  echo "  podman build -t $image -f $here/Containerfile $here"
  exit 0
fi

echo "build.sh: ${podman[*]} build -t $image"
"${podman[@]}" build -t "$image" -f "$here/Containerfile" "$here"
