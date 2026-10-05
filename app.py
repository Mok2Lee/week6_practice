"""Compose에서 실행하는 요청 발생기: 하나의 작업 스레드로 전송 속도를 조절합니다."""
import atexit
from collections import deque
import json
import os
import threading
import time
from urllib import error, request as http_request

from flask import Flask, jsonify, request


class RequestSender:
    MAX_RPM = 250

    def __init__(self, target_base, transport=None):
        self.target_base = target_base.rstrip("/")
        self._transport = transport or self._post_request
        self._condition = threading.Condition()
        self._rpm = 40
        self._running = False
        self._closed = False
        self._thread = None
        self._next_send = 0.0
        self._sequence = 0
        self._success = 0
        self._failed = 0
        self._last_error = None
        self._last_pod = None
        self._function = "projects"
        self._last_result = None
        self._recent = deque()

    def _post_request(self, sequence, function):
        # 주소는 실행 환경에서 정합니다. 웹 화면에서 임의의 주소를 입력하지 않습니다.
        if function == "projects":
            url = self.target_base + "/api/projects?category=web&q=%EC%98%88%EC%95%BD"
            outgoing = http_request.Request(url, method="GET")
        else:
            # 이전 시간에 사용한 소개글 분량 검사 API에 같은 소개글을 반복 전송합니다.
            text = ("우리 팀은 교내 공간 예약 서비스를 만듭니다. 학생들은 빈 강의실과 스터디룸을 검색하고, "
                    "원하는 시간에 공간을 예약할 수 있습니다. 관리자 화면에서는 예약 현황과 사용 통계를 "
                    "확인하여 공간을 효율적으로 운영합니다.")
            payload = json.dumps({"text": text}).encode("utf-8")
            outgoing = http_request.Request(self.target_base + "/api/analyze", data=payload, method="POST",
                                           headers={"Content-Type": "application/json"})
        with http_request.urlopen(outgoing, timeout=4) as response:
            result = json.loads(response.read(65536))
            if not isinstance(result, dict):
                raise ValueError("API 응답 형식이 올바르지 않습니다.")
            return {"pod": response.headers.get("X-Pod-Name") or result.get("pod"), "result": result}

    def set_function(self, function):
        if function not in ("projects", "analyze"):
            raise ValueError("프로젝트 검색 또는 소개글 분량 검사를 선택하세요.")
        with self._condition:
            self._function = function

    def set_rate(self, rpm):
        if isinstance(rpm, bool) or not isinstance(rpm, int) or not 0 <= rpm <= self.MAX_RPM:
            raise ValueError("요청 수는 분당 0~250의 정수로 입력하세요.")
        with self._condition:
            self._rpm = rpm
            if rpm == 0:
                self._running = False
            self._next_send = time.monotonic()
            self._condition.notify_all()

    def start(self):
        with self._condition:
            if self._rpm == 0:
                raise ValueError("분당 요청 수를 1 이상으로 설정하세요.")
            if self._closed:
                raise ValueError("요청 발생기가 종료되었습니다.")
            if not self._running:
                self._running = True
                self._next_send = time.monotonic()
                self._condition.notify_all()

    def stop(self):
        with self._condition:
            self._running = False
            self._condition.notify_all()

    def start_worker(self):
        with self._condition:
            if self._thread is None:
                self._thread = threading.Thread(target=self._work, name="request-sender", daemon=True)
                self._thread.start()

    def close(self):
        with self._condition:
            self._closed = True
            self._running = False
            self._condition.notify_all()
        if self._thread is not None:
            self._thread.join(timeout=5)

    def _work(self):
        while True:
            with self._condition:
                while not self._closed and (not self._running or self._rpm == 0):
                    self._condition.wait()
                if self._closed:
                    return
                wait_seconds = self._next_send - time.monotonic()
                if wait_seconds > 0:
                    self._condition.wait(timeout=wait_seconds)
                    continue
                self._next_send = time.monotonic() + 60 / self._rpm
            self.send_once()
            # 응답이 늦어도 밀린 요청을 한꺼번에 보내지 않습니다.
            with self._condition:
                self._next_send = max(self._next_send, time.monotonic())

    def send_once(self):
        with self._condition:
            self._sequence += 1
            sequence = self._sequence
            function = self._function
        started = time.monotonic()
        succeeded, pod, message = False, None, None
        try:
            result = self._transport(sequence, function)
            pod = result.get("pod")
            succeeded = True
        except error.HTTPError as exc:
            message = f"API 응답 오류: HTTP {exc.code}. 수신 프로젝트를 확인하세요."
        except (error.URLError, TimeoutError, OSError):
            message = "연결 실패: week6 실행과 8080 포트 연결을 확인하세요."
        except (ValueError, json.JSONDecodeError):
            message = "API 응답 형식을 확인하세요."
        elapsed_ms = (time.monotonic() - started) * 1000
        with self._condition:
            if succeeded:
                self._success += 1
                self._last_pod = pod
                returned = result.get("result", {})
                self._last_result = (f"프로젝트 {returned.get('count', '—')}개 검색됨" if function == "projects"
                                     else f"소개글 {returned.get('characters', '—')}자 · "
                                     + ("권장 분량 충족" if returned.get("within_range") else "분량 조정 필요"))
                self._last_error = None
            else:
                self._failed += 1
                self._last_error = message
            self._recent.append((time.monotonic(), succeeded, elapsed_ms))

    def status(self):
        with self._condition:
            now = time.monotonic()
            while self._recent and self._recent[0][0] <= now - 60:
                self._recent.popleft()
            latencies = [entry[2] for entry in self._recent]
            return {
                "running": self._running, "target_rpm": self._rpm,
                "sent": self._sequence, "success": self._success, "failed": self._failed,
                "sent_last_minute": len(self._recent),
                "success_last_minute": sum(entry[1] for entry in self._recent),
                "average_latency_ms": round(sum(latencies) / len(latencies), 1) if latencies else 0,
                "last_pod": self._last_pod, "last_error": self._last_error,
                "function": self._function, "last_result": self._last_result,
            }


def create_app(sender):
    app = Flask(__name__, static_folder="static", static_url_path="")
    app.json.ensure_ascii = False
    app.config["MAX_CONTENT_LENGTH"] = 4096

    @app.get("/")
    def index():
        return app.send_static_file("index.html")

    @app.get("/api/health")
    def health():
        return jsonify(status="ok", service="week6_sender")

    @app.get("/api/status")
    def status():
        return jsonify(sender.status())

    @app.post("/api/rate")
    def rate():
        data = request.get_json(silent=True)
        try:
            sender.set_rate(data.get("rpm") if isinstance(data, dict) else None)
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        return jsonify(sender.status())

    @app.post("/api/function")
    def function():
        data = request.get_json(silent=True)
        try:
            sender.set_function(data.get("function") if isinstance(data, dict) else None)
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        return jsonify(sender.status())

    @app.post("/api/start")
    def start():
        try:
            sender.start()
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        return jsonify(sender.status())

    @app.post("/api/stop")
    def stop():
        sender.stop()
        return jsonify(sender.status())

    return app


if __name__ == "__main__":
    controller = RequestSender(os.environ.get("TARGET_BASE", "http://host.docker.internal:8080"))
    controller.start_worker()
    atexit.register(controller.close)
    create_app(controller).run(host="0.0.0.0", port=5000, threaded=True, debug=False, use_reloader=False)
