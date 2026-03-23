cat > vercel_install.sh << 'EOF'
#!/bin/bash
export FLUTTER_ALLOW_ROOT=true

if cd flutter; then
  git pull && cd ..
else
  git clone https://github.com/flutter/flutter.git --branch 3.29.2 --single-branch --depth 1
fi

export PATH="$PATH:`pwd`/flutter/bin"
flutter --version
flutter config --enable-web
flutter clean
EOF