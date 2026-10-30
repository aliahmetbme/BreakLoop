#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
onboarding_build=$(mktemp -d /tmp/breakloop-onboarding.XXXXXX)
sed '/^import FamilyControls$/d' BreakLoop/Features/Onboarding/OnboardingViewModel.swift > "$onboarding_build/OnboardingViewModel.swift"
swiftc -module-cache-path "$onboarding_build/module-cache" "$onboarding_build/OnboardingViewModel.swift" Tests/OnboardingPermissionTests.swift -o "$onboarding_build/checks"
"$onboarding_build/checks"
