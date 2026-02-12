#!/bin/sh
set -e

# Flutter SDK 설치
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

# Flutter 의존성 설치
flutter precache --ios
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

# CocoaPods 설치 및 실행
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
gem install cocoapods
pod install
