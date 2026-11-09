"""Unduh foto wajah contoh (dataset uji DeepFace) untuk test pengenalan wajah.

img1, img2, img4 = orang yang sama; img3 = orang lain.
"""
import urllib.request
from pathlib import Path

BASE = "https://raw.githubusercontent.com/serengil/deepface/master/tests/unit/dataset"
DEST = Path(__file__).resolve().parent / "fixtures"


def main():
    DEST.mkdir(exist_ok=True)
    for name in ("img1.jpg", "img2.jpg", "img3.jpg", "img4.jpg"):
        target = DEST / name
        if target.exists():
            continue
        print(f"Mengunduh {name} ...")
        urllib.request.urlretrieve(f"{BASE}/{name}", target)
    print(f"Selesai: {DEST}")


if __name__ == "__main__":
    main()
