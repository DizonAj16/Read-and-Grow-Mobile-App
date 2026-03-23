#!/bin/bash
export FLUTTER_ALLOW_ROOT=true

if cd flutter; then
  git pull && cd ..
else
  git clone https://github.com/flutter/flutter.git -b 3.27.4 --depth 1
fi

export PATH="$PATH:`pwd`/flutter/bin"
flutter config --enable-web
flutter clean