#!/bin/sh
set -e

echo "=== Flutter SDK 설치 ==="
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin:$PATH"

echo "=== Flutter doctor ==="
flutter doctor -v

echo "=== Flutter 의존성 설치 ==="
flutter precache --ios
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

echo "=== CocoaPods 설치 ==="
gem install cocoapods --user-install
export PATH="$HOME/.gem/ruby/$(ruby -e 'puts RUBY_VERSION')/bin:$PATH"

echo "=== Pod install ==="
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod install

echo "=== 완료 ==="
