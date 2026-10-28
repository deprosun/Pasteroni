#!/bin/zsh
# Build Pasteroni and install it to /Applications, then relaunch it.
set -e
cd "$(dirname "$0")"
./build.sh
pkill -x Pasteroni 2>/dev/null || true
sleep 1
rm -rf /Applications/Pasteroni.app
cp -R Pasteroni.app /Applications/
open /Applications/Pasteroni.app
echo "Installed to /Applications/Pasteroni.app"
