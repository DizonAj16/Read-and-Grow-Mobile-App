#!/bin/bash
if cd flutter; then
  git pull && cd ..
else
  git clone https://github.com/flutter/flutter.git
fi
export FLUTTER_ALLOW_ROOT=true
flutter/bin/flutter config --enable-web
flutter/bin/flutter clean