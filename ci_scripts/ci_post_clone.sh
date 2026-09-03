#!/bin/sh
set -eu

repo="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
cd "$repo"

echo "CI post-clone: repo=$repo"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
echo "xcodegen $(xcodegen --version)"
xcodegen generate

test -d TrainOrRest.xcodeproj
test -f TrainOrRest.xcodeproj/xcshareddata/xcschemes/TrainOrRest.xcscheme
echo "Generated TrainOrRest.xcodeproj"
