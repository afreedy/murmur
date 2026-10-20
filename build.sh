#!/bin/zsh
set -eu
cd "${0:A:h}"
app_dir="build/Murmur.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library -O \
  App.swift Audio.swift Hotkey.swift PipeWorker.swift TextTarget.swift Theme.swift Views.swift Scratchpad.swift History.swift \
  -o "$app_dir/Contents/MacOS/CodexLuna"
cp Info.plist "$app_dir/Contents/Info.plist"
cp worker.py luna.py jobs.py "$app_dir/Contents/Resources/"
cp Assets/DockRounded.png Assets/Status-template.png "$app_dir/Contents/Resources/"
cp Assets/Murmur-icon.png "$app_dir/Contents/Resources/"
cp Assets/StatusIcon.png "$app_dir/Contents/Resources/"
xcrun actool "$PWD/Assets/Murmur.icon" --compile "$PWD/$app_dir/Contents/Resources/" --platform macosx --minimum-deployment-target 14.0 --app-icon Murmur --output-partial-info-plist "$PWD/build/icon-info.plist" --output-format human-readable-text
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile Murmur' -c 'Add :CFBundleIconName string Murmur' "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier com.afreed.codexluna --requirements '=designated => identifier "com.afreed.codexluna"'  "$app_dir"
"$app_dir/Contents/MacOS/CodexLuna" --self-check
codesign --verify --strict "$app_dir"
printf '%s\n' "Built $app_dir"
