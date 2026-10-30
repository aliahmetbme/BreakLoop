#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
legal_build=$(mktemp -d /tmp/breakloop-legal.XXXXXX)
swiftc -module-cache-path "$legal_build/module-cache" \
    BreakLoop/Features/Legal/LegalPublication.swift \
    BreakLoop/Features/Legal/LegalLinksViewModel.swift \
    Tests/LegalPublicationTests.swift -o "$legal_build/checks"
"$legal_build/checks"
