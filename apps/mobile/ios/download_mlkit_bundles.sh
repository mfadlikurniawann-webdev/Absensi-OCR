#!/bin/bash
#
# Unduh resource model ML Kit Face Detection untuk build iOS.
#
# Plugin google_mlkit_face_detection 1.x memakai Swift Package Manager, dan
# SwiftPM tidak menyertakan file model ke dalam app secara otomatis. Project
# Xcode (grup "MLKit Bundles") mengharapkan bundle berada di ios/mlkit_bundles/.
#
# Jalankan SEKALI di Mac sebelum build iOS pertama (dan bila versi ML Kit berubah):
#   cd mobile && bash ios/download_mlkit_bundles.sh
#
set -euo pipefail

VERSION="${1:-9.0.2}"   # harus sama dengan versi google-mlkit-swiftpm di plugin
BUNDLE="GoogleMVFaceDetectorResources.bundle"
URL="https://github.com/d-date/google-mlkit-swiftpm/releases/download/${VERSION}/${BUNDLE}.zip"
DEST_DIR="$(cd "$(dirname "$0")" && pwd)/mlkit_bundles"

if [ -d "${DEST_DIR}/${BUNDLE}" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "${BUNDLE} sudah ada di ${DEST_DIR} (FORCE=1 untuk unduh ulang)."
  exit 0
fi

mkdir -p "${DEST_DIR}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Mengunduh ${BUNDLE} (ML Kit ${VERSION}) ..."
curl -fL --retry 5 --retry-delay 5 -o "${TMP}/${BUNDLE}.zip" "${URL}"
rm -rf "${DEST_DIR:?}/${BUNDLE}"
unzip -q -o "${TMP}/${BUNDLE}.zip" -d "${DEST_DIR}"

if [ ! -d "${DEST_DIR}/${BUNDLE}" ]; then
  echo "Gagal: ${BUNDLE} tidak ditemukan setelah ekstrak." >&2
  exit 1
fi
echo "Selesai: ${DEST_DIR}/${BUNDLE}"
