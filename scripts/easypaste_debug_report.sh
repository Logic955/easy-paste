#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${HOME}/Library/Application Support/EasyPaste/state.json"
SQLITE_FILE="${HOME}/Library/Application Support/EasyPaste/EasyPaste.sqlite"
BLOBS_DIR="${HOME}/Library/Application Support/EasyPaste/Blobs"
PERF_LOG="${HOME}/Library/Application Support/EasyPaste/performance.log"
REPORT_FILE="${1:-/tmp/easypaste-debug-report.txt}"

{
  echo "# EasyPaste Debug Report"
  date "+Generated: %Y-%m-%d %H:%M:%S %z"
  echo

  echo "## App"
  pgrep -fl "/Applications/EasyPaste.app/Contents/MacOS/EasyPaste" || true
  echo

  echo "## State"
  echo "SQLite:"
  if [[ -f "${SQLITE_FILE}" ]]; then
    du -h "${SQLITE_FILE}"
    sqlite3 "${SQLITE_FILE}" 'SELECT "items=" || COUNT(*) FROM items;'
    sqlite3 "${SQLITE_FILE}" 'SELECT "pinboards=" || COUNT(*) FROM pinboards;'
    sqlite3 "${SQLITE_FILE}" 'SELECT "imageBlobBytes=" || COALESCE(SUM(image_byte_count),0) FROM items;'
    sqlite3 "${SQLITE_FILE}" 'SELECT "htmlBlobBytes=" || COALESCE(SUM(html_byte_count),0) FROM items;'
    sqlite3 "${SQLITE_FILE}" 'SELECT "rtfBlobBytes=" || COALESCE(SUM(rtf_byte_count),0) FROM items;'
  else
    echo "No sqlite file at ${SQLITE_FILE}"
  fi
  echo
  echo "Blobs:"
  if [[ -d "${BLOBS_DIR}" ]]; then
    du -sh "${BLOBS_DIR}"
    find "${BLOBS_DIR}" -type f | wc -l | awk '{print "blobFiles="$1}'
  else
    echo "No blobs directory at ${BLOBS_DIR}"
  fi
  echo
  echo "Legacy JSON:"
  if [[ -f "${STATE_FILE}" ]]; then
    du -h "${STATE_FILE}"
    jq -r '"items=\(.items|length)"' "${STATE_FILE}"
    jq -r '
      [.items[] | (.kind // "unknown")] | group_by(.)[] | "\(.[0])=\(length)"
    ' "${STATE_FILE}"
    jq -r '
      "maxHtmlBase64Bytes=\([.items[] | ((.htmlDataBase64 // "")|length)] | max // 0)"
    ' "${STATE_FILE}"
    jq -r '
      "maxImageBase64Bytes=\([.items[] | ((.imagePNGBase64 // "")|length)] | max // 0)"
    ' "${STATE_FILE}"
    echo
    echo "Recent items:"
    jq -r '.items[0:8][] | [.kind, ((.text // "")|length), ((.rtfDataBase64 // "")|length), ((.htmlDataBase64 // "")|length), ((.imagePNGBase64 // "")|length), (.sourceApp // "")] | @tsv' "${STATE_FILE}"
  else
    echo "No state file at ${STATE_FILE}"
  fi
  echo

  echo "## Current Pasteboard Metadata"
  swift - <<'SWIFT'
import AppKit
let pb = NSPasteboard.general
print("changeCount=\(pb.changeCount)")
let types = pb.types ?? []
print("typeCount=\(types.count)")
for type in types {
    let bytes = pb.data(forType: type)?.count ?? -1
    print("\(type.rawValue)\t\(bytes)")
}
print("stringChars=\(pb.string(forType: .string)?.count ?? -1)")
SWIFT
  echo

  echo "## Settings Summary"
  if [[ -f "${SQLITE_FILE}" ]]; then
    sqlite3 "${SQLITE_FILE}" "SELECT value FROM kv_store WHERE key='preferences';" | jq -r '
      "pasteDestination=\(.pasteDestination // "activeApp")",
      "alwaysPastePlainText=\(.alwaysPastePlainText // false)",
      "historyRetention=\(.historyRetention // "forever")",
      "debugPerformance=\(.debugPerformance // false)",
      "showDuringScreenSharing=\(.showDuringScreenSharing // true)",
      "generateLinkPreviews=\(.generateLinkPreviews // true)",
      "ignoredApplications=\((.ignoredApplications // [])|length)"
    ' 2>/dev/null || echo "Could not read settings summary"
  else
    echo "No sqlite settings available"
  fi
  echo

  echo "## Recommended Black-box Samples"
  echo "- Sublime/Text editor: 5k+ plain code block; expect plain text only, immediate first card."
  echo "- Browser/WeChat rich text: expect HTML/RTF preserved on original paste."
  echo "- cmux terminal text: expect plain text paste, no synthesized rich styling."
  echo "- Image copy: expect card appears before OCR/backfill work."
  echo "- URL and Git clone address: expect kind=url and original string paste."
  echo

  echo "## Performance Log Query"
  echo "tail -120 \"${PERF_LOG}\""
  echo "log show --predicate 'process == \"EasyPaste\" AND eventMessage CONTAINS \"EasyPastePerf\"' --last 10m --style compact"
  echo
  echo "## Recent Performance Log"
  if [[ -f "${PERF_LOG}" ]]; then
    tail -120 "${PERF_LOG}"
  else
    echo "No performance log at ${PERF_LOG}"
  fi
} > "${REPORT_FILE}"

echo "${REPORT_FILE}"
