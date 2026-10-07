import http.client
import json
import threading
import unittest

import server


class RelayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        server.CONFIG = {"read_secret": "phone-test", "write_secret": "pc-test"}
        cls.http = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        cls.thread = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.thread.join()

    def setUp(self):
        server.TOKENS.clear()
        server.clear_want()
        with server.RESULTS_LOCK:
            server.RESULTS.clear()
        with server.PASSWORD_LOCK:
            server.PASSWORD["value"] = None

    def request(self, path, payload, key):
        conn = http.client.HTTPConnection(*self.http.server_address, timeout=3)
        conn.request("POST", path, json.dumps(payload), {"X-Ninegram-Key": key, "Content-Type": "application/json"})
        response = conn.getresponse()
        code, body = response.status, response.read()
        conn.close()
        return code, json.loads(body) if body else None

    def test_qr_acceptance_is_not_desktop_completion(self):
        self.request("/v1/token", {"token": "first"}, "pc-test")
        self.request("/v1/consume", {"token": "first"}, "phone-test")
        self.assertEqual(self.request("/v1/result", {"token": "first"}, "phone-test"), (200, {"status": "pending"}))
        self.request("/v1/finish", {"token": "first", "success": True}, "pc-test")
        self.assertEqual(self.request("/v1/result", {"token": "first"}, "phone-test"), (200, {"status": "complete"}))

    def test_failed_password_can_be_retried_as_new_login(self):
        self.request("/v1/finish", {"token": "failed", "success": False}, "pc-test")
        self.assertEqual(self.request("/v1/result", {"token": "failed"}, "phone-test")[1]["status"], "failed")
        self.assertEqual(self.request("/v1/result", {"token": "new"}, "phone-test")[1]["status"], "pending")

    def test_stale_consume_preserves_current_token_and_request(self):
        server.TOKENS.put("newer")
        server.note_want()
        self.request("/v1/consume", {"token": "stale"}, "phone-test")
        self.assertEqual(server.TOKENS.get(), "newer")
        self.assertIsNotNone(server.want_age())

    def test_relay_preserves_ciphertext_and_delivers_it_once(self):
        envelope = "ng1:opaque-encrypted-test-envelope"
        self.assertEqual(self.request("/v1/password", {"password": envelope}, "phone-test")[0], 200)
        self.assertEqual(self.request("/v1/password/take", {}, "pc-test"), (200, {"password": envelope}))
        self.assertEqual(self.request("/v1/password/take", {}, "pc-test"), (204, None))

    def test_phone_cannot_report_pc_success_or_read_password(self):
        self.assertEqual(self.request("/v1/finish", {"token": "token", "success": True}, "phone-test")[0], 401)
        self.assertEqual(self.request("/v1/password/take", {}, "phone-test")[0], 401)
        self.assertEqual(self.request("/v1/result", {}, "pc-test")[0], 401)

    def test_password_is_bound_to_login_and_cleared_on_completion(self):
        self.request("/v1/password", {"password": "ng1:bound", "token": "current"}, "phone-test")
        self.assertEqual(self.request("/v1/password/take", {"token": "older"}, "pc-test"), (204, None))
        self.assertEqual(self.request("/v1/password/take", {"token": "current"}, "pc-test"), (200, {"password": "ng1:bound"}))
        self.request("/v1/password", {"password": "ng1:unused", "token": "current"}, "phone-test")
        self.request("/v1/finish", {"token": "current", "success": True}, "pc-test")
        self.assertEqual(self.request("/v1/password/take", {"token": "current"}, "pc-test"), (204, None))

    def test_invalid_payload_is_rejected(self):
        self.assertEqual(self.request("/v1/finish", [1, 2], "pc-test")[0], 400)
        self.assertEqual(self.request("/v1/finish", {"token": "token", "success": "false"}, "pc-test")[0], 400)


if __name__ == "__main__":
    unittest.main()
