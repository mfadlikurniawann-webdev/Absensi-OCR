import os
import sys
import tempfile
from pathlib import Path

import pytest

SERVER_DIR = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"

# Konfigurasi harus di-set sebelum app diimpor (dibaca saat import).
os.environ["DB_PATH"] = str(Path(tempfile.mkdtemp()) / "import.db")
os.environ["PRELOAD_MODEL"] = "0"
os.environ["ADMIN_USERNAME"] = "admin"
os.environ["ADMIN_PASSWORD"] = "rahasia-test"
os.environ["SECRET_KEY"] = "test-secret"
os.environ["ATTENDANCE_COOLDOWN_MINUTES"] = "5"
sys.path.insert(0, str(SERVER_DIR))

import app as server  # noqa: E402


@pytest.fixture
def backend(tmp_path, monkeypatch):
    """Modul app dengan database kosong per test."""
    monkeypatch.setattr(server, "DB_PATH", str(tmp_path / "test.db"))
    server.init_db()
    return server


@pytest.fixture
def client(backend):
    backend.app.config["TESTING"] = True
    return backend.app.test_client()


@pytest.fixture
def admin_headers(client):
    resp = client.post(
        "/api/admin/login", json={"username": "admin", "password": "rahasia-test"}
    )
    return {"Authorization": f"Bearer {resp.json['token']}"}


def face_image(name):
    path = FIXTURES / name
    if not path.exists():
        pytest.skip("Foto contoh belum ada; jalankan python tests/download_fixtures.py")
    return path.read_bytes()
