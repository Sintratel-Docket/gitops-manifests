import json
import time
import urllib.error
import urllib.request


def request(method, url, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read()
        return error.code, json.loads(raw) if raw else None


def wait_for(url, expected_text=None, attempts=60):
    error = None
    for _ in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                text = response.read().decode()
                if expected_text is None or expected_text in text:
                    return text
        except Exception as caught:
            error = caught
        time.sleep(1)
    raise AssertionError("service did not become ready: {} ({})".format(url, error))


wait_for("http://localhost:8000/version", "Auth API")
wait_for("http://localhost:8083/metrics", "jvm_")
wait_for("http://localhost:9100/metrics")

# Integration auth-api -> users-api: login can only succeed if the signed
# service JWT is accepted and the requested user is returned upstream.
status, login = request("POST", "http://localhost:8000/login", {"username": "admin", "password": "admin"})
assert status == 200 and login.get("accessToken"), (status, login)
token = login["accessToken"]

# Integration auth-api -> todos-api: the login token is accepted, while an
# unauthenticated request is blocked.
assert request("GET", "http://localhost:8082/todos")[0] == 401
status, before = request("GET", "http://localhost:8082/todos", token=token)
assert status == 200 and "1" in before, (status, before)

# Critical E2E: login -> create -> see on board -> update status.
status, created = request("POST", "http://localhost:8082/todos", {"content": "CI critical flow"}, token)
assert status == 200 and created["status"] == "pending", (status, created)
status, board = request("GET", "http://localhost:8082/todos", token=token)
assert status == 200 and str(created["id"]) in board, (status, board)
status, updated = request("PATCH", "http://localhost:8082/todos/{}".format(created["id"]), {"status": "done"}, token)
assert status == 200 and updated["status"] == "done", (status, updated)

# Integration todos-api -> Redis -> log-message-processor: the CREATE/UPDATE
# events must be consumed by the worker, exposed through its success metric.
wait_for("http://localhost:9100/metrics", 'docket_worker_messages_processed_total{service="log-message-processor"} 2.0')
print("PASS: authentication, board flow, status update and Redis event processing")
