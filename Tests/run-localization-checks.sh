#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
localization_build=$(mktemp -d /tmp/breakloop-localization.XXXXXX)
mkdir -p "$localization_build/App.bundle" "$localization_build/Shield.bundle"
for localization_bundle in App Shield; do
    cat > "$localization_build/$localization_bundle.bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>BreakLoop.LocalizationTests.$localization_bundle</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
PLIST
    xcrun xcstringstool compile BreakLoop/SharedErrors.xcstrings --output-directory "$localization_build/$localization_bundle.bundle"
done
xcrun xcstringstool compile BreakLoop/Localizable.xcstrings --output-directory "$localization_build/App.bundle"
xcrun xcstringstool compile ShieldConfigurationExtension/Localizable.xcstrings --output-directory "$localization_build/Shield.bundle"
swiftc -module-cache-path "$localization_build/module-cache" Tests/LocalizationTests.swift -o "$localization_build/checks"
"$localization_build/checks" "$localization_build"
