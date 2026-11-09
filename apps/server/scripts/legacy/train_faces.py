import cv2
from deepface import DeepFace
import sqlite3, json, os
import numpy as np
from scipy.spatial.distance import cosine

DB_PATH = "absensi.db"

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # cek apakah kolom 'embedding' ada
    cur.execute("PRAGMA table_info(users)")
    cols = [row[1] for row in cur.fetchall()]
    if "embedding" not in cols:
        cur.execute("DROP TABLE IF EXISTS users")

    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            embedding TEXT NOT NULL
        )
    """)
    conn.commit()
    conn.close()

def is_duplicate(embedding, threshold=0.4):
    """Cek apakah wajah sudah pernah terdaftar."""
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT id, name, embedding FROM users")
    users = cur.fetchall()
    conn.close()

    for user in users:
        try:
            stored_embedding = np.array(json.loads(user[2]))
            distance = cosine(embedding, stored_embedding)
            if distance < threshold:  # mirip → wajah sama
                return True, user[1]
        except Exception as e:
            print(f"[X] Error cek duplikat untuk {user[1]}: {e}")
    return False, None

def register_user(name):
    cap = cv2.VideoCapture(0)
    print("Tekan 'q' untuk capture wajah...")

    while True:
        ret, frame = cap.read()
        cv2.imshow("Registrasi Wajah", frame)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            cv2.imwrite("temp.jpg", frame)
            break

    cap.release()
    cv2.destroyAllWindows()

    try:
        embedding = DeepFace.represent(img_path="temp.jpg", model_name="Facenet")[0]["embedding"]

        # 🔎 cek duplikasi wajah
        is_dup, existing_name = is_duplicate(embedding)
        if is_dup:
            print(f"[X] Registrasi ditolak: wajah sudah terdaftar atas nama '{existing_name}'")
            return

        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("INSERT INTO users (name, embedding) VALUES (?, ?)", 
                    (name, json.dumps(embedding)))
        conn.commit()
        conn.close()

        print(f"[OK] Data wajah {name} berhasil disimpan ke database.")
    except Exception as e:
        print("Gagal mendaftarkan wajah:", e)

if __name__ == "__main__":
    init_db()
    nama = input("Masukkan nama civitas: ")
    register_user(nama)
