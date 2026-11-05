import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

PROJECT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_DIR / "app"))


class PanelTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.temp_dir.name)
        (self.data_dir / "users.json").write_text("{}", encoding="utf-8")
        (self.data_dir / "users-trash.json").write_text("{}", encoding="utf-8")
        (self.data_dir / "multisub.log").write_text("", encoding="utf-8")

        env = {
            "MULTISUB_DATA_DIR": str(self.data_dir),
            "MULTISUB_LOG_FILE": str(self.data_dir / "multisub.log"),
            "APP_TEMPLATES_DIR": str(PROJECT_DIR / "templates"),
            "PANEL_USERNAME": "testadmin",
            "PANEL_PASSWORD": "Test-Only-Password",
            "PANEL_SECRET_KEY": "test-only-secret-key",
            "PANEL_COOKIE_SECURE": "false",
        }

        self.env_patch = patch.dict(os.environ, env)
        self.env_patch.start()

        import importlib

        # Reload the module so file paths use this test's temporary directory.
        sys.modules.pop("panel", None)
        panel = importlib.import_module("panel")
        self.panel = panel
        self.client = panel.app.test_client()
        self.client.testing = True
        self.assertFalse(panel.app.config["SESSION_COOKIE_SECURE"])

        response = self.client.post(
            "/login",
            data={
                "username": "testadmin",
                "password": "Test-Only-Password",
            },
        )
        self.assertEqual(response.status_code, 302)

    def tearDown(self):
        self.env_patch.stop()
        self.temp_dir.cleanup()

    def read_json(self, filename):
        return json.loads(
            (self.data_dir / filename).read_text(encoding="utf-8")
        )

    def test_create_user(self):
        response = self.client.post(
            "/user/create",
            data={"name": "Test User"},
        )
        self.assertEqual(response.status_code, 302)

        users = self.read_json("users.json")
        self.assertEqual(len(users), 1)

        token, user = next(iter(users.items()))
        self.assertEqual(user["name"], "Test User")
        self.assertTrue(user["enabled"])
        self.assertEqual(user["sources"], [])
        self.assertEqual(len(token), 48)

    def test_update_user(self):
        token = "a" * 48
        (self.data_dir / "users.json").write_text(
            json.dumps({
                token: {
                    "name": "Before",
                    "enabled": True,
                    "sources": [],
                }
            }),
            encoding="utf-8",
        )

        response = self.client.post(
            f"/user/{token}/settings",
            data={"name": "After", "enabled": "0"},
        )
        self.assertEqual(response.status_code, 302)

        user = self.read_json("users.json")[token]
        self.assertEqual(user["name"], "After")
        self.assertFalse(user["enabled"])

    def test_delete_and_restore_user(self):
        token = "b" * 48
        original_user = {
            "name": "Recover Me",
            "enabled": True,
            "sources": ["https://example.invalid/sub"],
        }
        (self.data_dir / "users.json").write_text(
            json.dumps({token: original_user}),
            encoding="utf-8",
        )

        response = self.client.post(f"/user/{token}/delete")
        self.assertEqual(response.status_code, 302)

        self.assertNotIn(token, self.read_json("users.json"))
        self.assertIn(token, self.read_json("users-trash.json"))

        response = self.client.post(f"/trash/{token}/restore")
        self.assertEqual(response.status_code, 302)

        self.assertEqual(self.read_json("users.json")[token], original_user)
        self.assertNotIn(token, self.read_json("users-trash.json"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
