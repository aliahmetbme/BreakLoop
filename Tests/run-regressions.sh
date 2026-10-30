#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d /tmp/breakloop-regressions.XXXXXX)
swiftc -module-cache-path "$build_dir/module-cache" \
  BreakLoop/Core/Domain/Models/BreakLoopDomainModels.swift \
  BreakLoop/Core/Domain/Services/UsageCycleCalculators.swift \
  BreakLoop/Core/Domain/Services/BLTimePresentation.swift \
  BreakLoop/Core/Domain/Services/AuthorizationStartupPolicy.swift \
  BreakLoop/Core/Infrastructure/Lifecycle/MonitoringLifecycle.swift \
  BreakLoop/Core/Infrastructure/Lifecycle/RuntimeFileStore.swift \
  BreakLoop/Core/Infrastructure/Persistence/RuntimeChangeSignal.swift \
  BreakLoop/Features/DashBoard/DashboardStateSynchronization.swift \
  BreakLoop/Core/Infrastructure/Logging/LogCatagory.swift \
  BreakLoop/Core/Infrastructure/Logging/PersistentLogStore.swift \
  BreakLoop/Core/Infrastructure/Logging/AppLogger.swift \
  Tests/LockContentionTests.swift \
  Tests/DeepFocusCoexistenceTests.swift \
  Tests/TimePresentationTests.swift \
  Tests/DiagnosticArchiveTests.swift \
  Tests/DashboardSynchronizationTests.swift \
  Tests/CooldownSelectionTests.swift \
  Tests/LifecycleTests.swift -o "$build_dir/lifecycle-tests"
"$build_dir/lifecycle-tests"
swift -module-cache-path "$build_dir/module-cache" Tests/LogicTests.swift
