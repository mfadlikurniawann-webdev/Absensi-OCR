import io

import cv2
import numpy as np
import pytest

from conftest import face_image


def upload(client, path, img, headers=None, **fields):
    data = dict(fields)
    if img is not None:
        data["image"] = (io.BytesIO(img), "face.jpg")
    return client.post(
        path, data=data, content_type="multipart/form-data", headers=headers or {}
    )


# ------------------------------------------------------------------ dasar


def test_health(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json["status"] == "ok"


def test_unknown_api_endpoint_returns_json_404(client):
    resp = client.get("/api/tidak-ada")
    assert resp.status_code == 404
    assert resp.json["success"] is False


# ------------------------------------------------------------- keamanan


def test_attendance_list_requires_admin(client):
    assert client.get("/absensi").status_code == 401
    assert client.get("/api/admin/attendance").status_code == 401


def test_attendance_by_user_id_requires_admin(client):
    assert client.post("/absensi", json={"user_id": 1}).status_code == 401


def test_admin_login(client):
    bad = client.post("/api/admin/login", json={"username": "admin", "password": "x"})
    assert bad.status_code == 401
    good = client.post(
        "/api/admin/login", json={"username": "admin", "password": "rahasia-test"}
    )
    assert good.status_code == 200 and good.json["token"]


def test_forged_token_rejected(client):
    headers = {"Authorization": "Bearer token-palsu"}
    assert client.get("/api/admin/summary", headers=headers).status_code == 401


def test_web_session_login(client):
    resp = client.post("/login", data={"username": "admin", "password": "rahasia-test"})
    assert resp.status_code == 302 and "/dashboard" in resp.headers["Location"]
    assert client.get("/absensi").status_code == 200
    assert client.get("/export/csv").status_code == 200


# ------------------------------------------------------------ validasi


def test_summary_on_empty_db(client, admin_headers):
    resp = client.get("/api/admin/summary", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json["total_users"] == 0 and resp.json["total_attendance"] == 0


def test_register_requires_photo_and_fields(client):
    assert upload(client, "/api/register", None, name="A", npm="1").status_code == 400
    assert upload(client, "/api/register", b"bukan gambar", name="A", npm="1").status_code == 400
    assert upload(client, "/api/register", b"x", name="", npm="1").status_code == 400


def test_invalid_date_filter(client, admin_headers):
    resp = client.get("/api/admin/attendance?date=29-09", headers=admin_headers)
    assert resp.status_code == 400


def test_registration_can_be_admin_only(client, backend, monkeypatch, admin_headers):
    monkeypatch.setattr(backend, "ALLOW_PUBLIC_REGISTER", False)
    resp = upload(client, "/api/register", b"x", name="A", npm="1")
    assert resp.status_code == 403
    resp = upload(client, "/api/register", b"x", headers=admin_headers, name="A", npm="1")
    assert resp.status_code == 400  # lolos otorisasi, gagal di validasi gambar


# ---------------------------------------------------- pengenalan wajah


@pytest.mark.face
def test_photo_without_face_is_rejected(client):
    blank = cv2.imencode(".jpg", np.full((480, 640, 3), 200, np.uint8))[1].tobytes()
    resp = upload(client, "/api/register", blank, name="A", npm="1")
    assert resp.status_code == 422


@pytest.mark.face
def test_register_and_attendance_flow(client, admin_headers):
    img1, img2, img3, img4 = (face_image(f"img{i}.jpg") for i in (1, 2, 3, 4))

    resp = upload(client, "/api/register", img1, name="Uji Satu", npm="9990001")
    assert resp.status_code == 201, resp.json
    user_id = resp.json["user"]["id"]

    # wajah yang sama / NPM yang sama ditolak
    assert upload(client, "/api/register", img2, name="Lain", npm="9990002").status_code == 409
    assert upload(client, "/api/register", img3, name="Lain", npm="9990001").status_code == 409

    # foto lain orang yang sama dikenali
    resp = upload(client, "/api/attendance", img2)
    assert resp.json["recognized"] and resp.json["name"] == "Uji Satu"
    assert resp.json["already_recorded"] is False

    # absen ulang dalam masa cooldown tidak dicatat dobel
    resp = upload(client, "/api/attendance", img4)
    assert resp.json["recognized"] and resp.json["already_recorded"] is True

    # orang lain tidak dikenali
    resp = upload(client, "/api/attendance", img3)
    assert resp.status_code == 200 and resp.json["recognized"] is False

    rows = client.get("/api/admin/attendance?q=Uji", headers=admin_headers).json
    assert rows["count"] == 1

    csv_text = client.get("/api/admin/export.csv", headers=admin_headers).data.decode()
    assert csv_text.startswith("\ufeffID,Name,NPM,Waktu") and "Uji Satu" in csv_text

    assert client.delete(f"/api/admin/users/{user_id}", headers=admin_headers).status_code == 200
    assert client.delete(f"/api/admin/users/{user_id}", headers=admin_headers).status_code == 404
