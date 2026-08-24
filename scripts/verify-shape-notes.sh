#!/usr/bin/env bash
# Builds and runs the shape-description checks of #93 against the app's own
# sources.
#
# Not part of the CI build, for the same reason as its sibling: the app has no
# test target, and this is a standalone executable rather than a scheme
# xcodebuild knows about. Run it when `Markup`, either exporter, the handoff
# contract or the stored history is touched — the first case in it is what
# stands between an added field and a deleted capture history.
set -euo pipefail

cd "$(dirname "$0")/.."
out="$(mktemp -d)/verify-shape-notes"

xcrun swiftc -O -target "$(uname -m)-apple-macos15.0" -o "$out" \
    Pinpoint/AgentTextFormat.swift \
    Pinpoint/AXSnapshot.swift \
    Pinpoint/CaptureRecord.swift \
    Pinpoint/Exporter.swift \
    Pinpoint/FileHandoff.swift \
    Pinpoint/HandoffContract.swift \
    Pinpoint/HandoffDocument.swift \
    Pinpoint/HandoffDocumentBuilder.swift \
    Pinpoint/Markup.swift \
    Pinpoint/MarkupMetrics.swift \
    Pinpoint/Pin.swift \
    Pinpoint/PinStyle.swift \
    Pinpoint/Redaction.swift \
    Pinpoint/TaskPreset.swift \
    Pinpoint/TextRecognizer.swift \
    Pinpoint/Theme.swift \
    scripts/verify-shape-notes.swift

exec "$out"
