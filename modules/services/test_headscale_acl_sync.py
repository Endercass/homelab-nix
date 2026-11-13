import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("headscale-acl-sync.py")
SPEC = importlib.util.spec_from_file_location("headscale_acl_sync", MODULE_PATH)
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class SynchronizerTests(unittest.TestCase):
    def test_policy_replaces_only_dynamic_admin_group(self):
        static = {"groups": {"group:other": ["other@"]}, "grants": []}
        rendered = json.loads(SYNC.render_policy(static, ["admin@"]))
        self.assertEqual(rendered["groups"]["group:other"], ["other@"])
        self.assertEqual(rendered["groups"]["group:tailscale_admins"], ["admin@"])

    def test_atomic_install_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "policy.hujson"
            self.assertIsNone(SYNC.atomic_install(path, '{"groups": {}}\n'))
            old = SYNC.atomic_install(path, '{"groups": {}}\n')
            self.assertEqual(old, b'{"groups": {}}\n')

    def test_duplicate_headscale_identity_fails(self):
        config = {"oidc_issuer": "https://issuer"}
        users = [
            {"providerIdentifier": "https://issuer/user-1", "loginName": "alice"},
            {"providerIdentifier": "https://issuer/user-1", "loginName": "alice"},
        ]
        with self.assertRaises(SYNC.SyncError):
            SYNC.resolve_users(config, ["user-1"], users)

    def test_missing_headscale_identity_fails(self):
        config = {"oidc_issuer": "https://issuer"}
        with self.assertRaises(SYNC.SyncError):
            SYNC.resolve_users(config, ["missing"], [])


if __name__ == "__main__":
    unittest.main()
