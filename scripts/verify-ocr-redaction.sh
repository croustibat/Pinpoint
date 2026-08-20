#!/usr/bin/env bash
# Builds and runs the redaction check of #49 against the app's own sources.
#
# Not part of the CI build: it exercises Vision's text recognizer, whose exact
# output is a model's and not a contract's, and a check that can go amber on an
# OS update has no business gating a merge. Run it when the recognizer, the
# mask, or either exporter is touched.
set -euo pipefail

cd "$(dirname "$0")/.."
out="$(mktemp -d)/verify-ocr-redaction"

xcrun swiftc -O -target "$(uname -m)-apple-macos15.0" -o "$out" \
    Pinpoint/AgentTextFormat.swift \
    Pinpoint/AXSnapshot.swift \
    Pinpoint/Exporter.swift \
    Pinpoint/FileHandoff.swift \
    Pinpoint/HandoffDocument.swift \
    Pinpoint/Markup.swift \
    Pinpoint/MarkupMetrics.swift \
    Pinpoint/Pin.swift \
    Pinpoint/PinStyle.swift \
    Pinpoint/Redaction.swift \
    Pinpoint/TaskPreset.swift \
    Pinpoint/TextRecognizer.swift \
    Pinpoint/Theme.swift \
    scripts/verify-ocr-redaction.swift

exec "$out"
