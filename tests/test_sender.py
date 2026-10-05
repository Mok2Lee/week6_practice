"""요청 속도 제어, 허용된 API 선택, 전송 결과, 중지 동작을 확인합니다."""
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import RequestSender, create_app


class SenderTests(unittest.TestCase):
    def make_sender(self, transport=None):
        return RequestSender("http://host.docker.internal:8080", transport=transport)

    def test_rate_limits_and_pause(self):
        sender = self.make_sender()
        for value in (-1, 251, True, 20.5, "40", None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                sender.set_rate(value)
        sender.set_rate(250)
        sender.start()
        self.assertTrue(sender.status()["running"])
        sender.set_rate(0)
        self.assertFalse(sender.status()["running"])
        with self.assertRaises(ValueError):
            sender.start()

    def test_two_allowed_apis_and_real_results(self):
        calls = []

        def transport(sequence, function):
            calls.append((sequence, function))
            result = {"count": 1} if function == "projects" else {"characters": 130, "within_range": True}
            return {"pod": "api-pod-a", "result": result}

        sender = self.make_sender(transport)
        sender.send_once()
        self.assertEqual(sender.status()["last_result"], "프로젝트 1개 검색됨")
        sender.set_function("analyze")
        sender.send_once()
        status = sender.status()
        self.assertEqual(calls, [(1, "projects"), (2, "analyze")])
        self.assertEqual(status["success_last_minute"], 2)
        self.assertEqual(status["last_pod"], "api-pod-a")
        self.assertIn("130자", status["last_result"])
        with self.assertRaises(ValueError):
            sender.set_function("http://elsewhere.invalid")

    def test_transport_failures_are_visible_and_do_not_crash(self):
        failures = [URLError("refused"), HTTPError("http://localhost", 503, "unavailable", {}, None)]
        for failure in failures:
            def transport(sequence, function):
                raise failure
            sender = self.make_sender(transport)
            sender.send_once()
            status = sender.status()
            self.assertEqual(status["sent_last_minute"], 1)
            self.assertEqual(status["failed"], 1)
            self.assertEqual(status["success"], 0)
            self.assertTrue(status["last_error"])
            self.assertGreaterEqual(status["average_latency_ms"], 0)

    def test_real_http_routes_and_pod_header(self):
        class Response:
            headers = {"X-Pod-Name": "api-pod-b"}
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, limit): return b'{"count":1,"characters":130,"within_range":true}'

        sender = self.make_sender()
        with patch("app.http_request.urlopen", return_value=Response()) as outgoing:
            result = sender._post_request(1, "projects")
            req = outgoing.call_args.args[0]
            self.assertEqual(req.get_method(), "GET")
            self.assertTrue(req.full_url.startswith("http://host.docker.internal:8080/api/projects?"))
            self.assertEqual(result["pod"], "api-pod-b")
            sender._post_request(2, "analyze")
            req = outgoing.call_args.args[0]
            self.assertEqual(req.get_method(), "POST")
            self.assertEqual(req.full_url, "http://host.docker.internal:8080/api/analyze")
            self.assertIn(b'"text"', req.data)

    def test_health_and_status_never_send_requests(self):
        sender = self.make_sender(lambda sequence, function: self.fail("unexpected request"))
        client = create_app(sender).test_client()
        for _ in range(3):
            self.assertEqual(client.get("/api/health").status_code, 200)
            self.assertEqual(client.get("/api/status").status_code, 200)
        self.assertEqual(sender.status()["sent"], 0)
        self.assertEqual(client.post("/api/rate", json={"rpm": 251}).status_code, 400)
        self.assertEqual(client.post("/api/function", json={"function": "https://bad.invalid"}).status_code, 400)
        self.assertEqual(client.post("/api/function", json={"function": "analyze"}).status_code, 200)

    def test_stop_allows_one_inflight_request_then_no_more(self):
        entered, release = threading.Event(), threading.Event()
        calls = []

        def transport(sequence, function):
            calls.append(sequence)
            entered.set()
            release.wait(timeout=2)
            return {"pod": "api-test", "result": {"count": 1}}

        sender = self.make_sender(transport)
        try:
            sender.set_rate(250)
            sender.start_worker()
            worker = sender._thread
            sender.start_worker()
            self.assertIs(sender._thread, worker)
            sender.start()
            self.assertTrue(entered.wait(timeout=2))
            sender.stop()
            release.set()
            sender.close()
            self.assertEqual(calls, [1])
            self.assertFalse(sender.status()["running"])
            self.assertEqual(sender.status()["success"], 1)
        finally:
            release.set()
            sender.close()


if __name__ == "__main__":
    unittest.main()
