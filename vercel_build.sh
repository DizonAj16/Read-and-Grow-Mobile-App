cat > vercel_build.sh << 'EOF'
#!/bin/bash
set -e
export FLUTTER_ALLOW_ROOT=true

# Clone Flutter if not present
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git --branch 3.29.2 --single-branch --depth 1
fi

export PATH="$PATH:$(pwd)/flutter/bin"
flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release --no-tree-shake-icons
EOF