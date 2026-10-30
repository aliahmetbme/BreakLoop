#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
terms_build=$(mktemp -d /tmp/breakloop-terms.XXXXXX)
for terms_mode in debug release; do
    if [ "$terms_mode" = debug ]; then
        swiftc -D DEBUG -module-cache-path "$terms_build/module-cache" BreakLoop/Features/Legal/LegalPublication.swift BreakLoop/Features/Legal/TermsAcceptanceModel.swift Tests/TermsAcceptanceTests.swift -o "$terms_build/$terms_mode"
    else
        swiftc -module-cache-path "$terms_build/module-cache" BreakLoop/Features/Legal/LegalPublication.swift BreakLoop/Features/Legal/TermsAcceptanceModel.swift Tests/TermsAcceptanceTests.swift -o "$terms_build/$terms_mode"
    fi
    "$terms_build/$terms_mode"
done
