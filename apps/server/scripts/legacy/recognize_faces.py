import cv2
from deepface import DeepFace
import sqlite3, json
import numpy as np
from scipy.spatial.distance import cosine
import requests

DB_PATH = "absensi.db"
API_URL = "http://127.0.0.1:5000/absensi"  # endpoint Flask

def load_users():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT id, name, embedding FROM users")
    users = cur.fetchall()
    conn.close()
    return users

def recognize_face():
    users = load_users()
    if not users:
        print("Belum ada user terdaftar di database!")
        return

    cap = cv2.VideoCapture(0)
    print("Tekan 'q' untuk capture absensi...")

    while True:
        ret, frame = cap.read()
        cv2.imshow("Absensi Wajah", frame)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            cv2.imwrite("absensi.jpg", frame)
            break

    cap.release()
    cv2.destroyAllWindows()

    try:
        current_embedding = DeepFace.represent(
            img_path="absensi.jpg", model_name="Facenet")[0]["embedding"]

        best_match = None
        min_distance = 1.0

        for user in users:
            stored_embedding = np.array(json.loads(user[2]))
            distance = cosine(current_embedding, stored_embedding)

            if distance < min_distance and distance < 0.4:
                min_distance = distance
                best_match = user

        if best_match:
            user_id, name, _ = best_match
            print(f"[ABSENSI] Wajah dikenali sebagai {name}")

            # Kirim request ke API Flask
            try:
                resp = requests.post(API_URL, json={"user_id": user_id})
                print("[API RESPONSE]", resp.json())
            except Exception as e:
                print("[X] Gagal menghubungi API:", e)

        else:
            print("[X] Wajah tidak dikenali")

    except Exception as e:
        print("Gagal melakukan absensi:", e)

if __name__ == "__main__":
    recognize_face()