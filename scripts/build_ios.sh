#!/bin/bash
flutter build ipa --release --dart-define-from-file=.env "$@"
