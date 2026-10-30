#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
journey_tests=${1:-Tests/FirstRunJourneyTests.swift}
journey_build=$(mktemp -d /tmp/breakloop-first-run.XXXXXX)
for journey_source in BreakLoop/Features/DashBoard/DashboardViewModel.swift BreakLoop/Features/FocusSetup/FocusSetupViewModel.swift BreakLoop/Core/Infrastructure/Lifecycle/MonitoringLifecycleFactory.swift; do
    sed '/^import FamilyControls$/d' "$journey_source" > "$journey_build/$(basename "$journey_source")"
done
swiftc -module-cache-path "$journey_build/module-cache" \
    BreakLoop/Core/Domain/Models/BreakLoopDomainModels.swift \
    BreakLoop/Core/Domain/Services/UsageCycleCalculators.swift \
    BreakLoop/Core/Infrastructure/Lifecycle/MonitoringLifecycle.swift \
    BreakLoop/Core/Infrastructure/Persistence/RuntimeChangeSignal.swift \
    BreakLoop/Core/Infrastructure/Logging/LogCatagory.swift \
    BreakLoop/Core/Infrastructure/Logging/PersistentLogStore.swift \
    BreakLoop/Core/Infrastructure/Logging/AppLogger.swift \
    BreakLoop/Features/DashBoard/DashboardStateSynchronization.swift \
    "$journey_build/DashboardViewModel.swift" "$journey_build/FocusSetupViewModel.swift" "$journey_build/MonitoringLifecycleFactory.swift" \
    Tests/FirstRunJourneyBoundary.swift "$journey_tests" -o "$journey_build/checks"
"$journey_build/checks"
