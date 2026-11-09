"""Klien webcam desktop untuk server absensi (pengganti skrip di legacy/).

Ambil foto dari webcam laptop lalu kirim ke API server.

    python scripts/webcam_client.py absen
    python scripts/webcam_client.py daftar --nama "Budi" --npm 2315061001

Tekan SPASI untuk ambil foto, Q / ESC untuk batal.
Butuh `pip install opencv-python requests` di virtualenv terpisah
(server memakai opencv headless yang tidak punya jendela kamera).
Alamat server: env API_URL (default http://127.0.0.1:5000).
"""
import argparse
import os
import sys

import cv2
import requests

API_URL = os.environ.get("API_URL", "http://127.0.0.1:5000").rstrip("/")


def capture_jpeg():
    cam = cv2.VideoCapture(0)
    if not cam.isOpened():
        sys.exit("Webcam tidak bisa dibuka.")
    try:
        while True:
            ok, frame = cam.read()
            if not ok:
                sys.exit("Gagal membaca frame webcam.")
            cv2.imshow("Absensi - SPASI: ambil foto, Q: batal", frame)
            key = cv2.waitKey(1) & 0xFF
            if key == ord(" "):
                ok, buf = cv2.imencode(".jpg", frame)
                return buf.tobytes() if ok else None
            if key in (ord("q"), 27):
                return None
    finally:
        cam.release()
        cv2.destroyAllWindows()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("absen", help="Absen dengan wajah")
    daftar = sub.add_parser("daftar", help="Daftarkan wajah baru")
    daftar.add_argument("--nama", required=True)
    daftar.add_argument("--npm", required=True)
    args = parser.parse_args()

    jpeg = capture_jpeg()
    if jpeg is None:
        print("Dibatalkan.")
        return

    files = {"image": ("face.jpg", jpeg, "image/jpeg")}
    if args.command == "absen":
        resp = requests.post(f"{API_URL}/api/attendance", files=files, timeout=90)
    else:
        resp = requests.post(
            f"{API_URL}/api/register",
            data={"name": args.nama, "npm": args.npm},
            files=files,
            timeout=90,
        )
    data = resp.json()
    print(data.get("message", data))
    if data.get("recognized"):
        print(f"  {data['name']} ({data['npm']}) - {data['waktu']}")


if __name__ == "__main__":
    main()
