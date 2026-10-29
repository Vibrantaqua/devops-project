"""Snake game web app: serves the game, a leaderboard API and Prometheus metrics."""
import os
import re
import threading
import time

from flask import Flask, Response, g, jsonify, request, send_from_directory
from prometheus_client import (CONTENT_TYPE_LATEST, Counter, Gauge, Histogram,
                               generate_latest)

app = Flask(__name__, static_folder="static", static_url_path="/static")
app.config["SECRET_KEY"] = os.environ.get("APP_SECRET_KEY", "dev-only-change-me")
VERSION = os.environ.get("APP_VERSION", "1.0.0")

NAME_RE = re.compile(r"^[A-Za-z0-9 _-]{1,12}$")
MAX_SCORE = 10000
TOP_N = 10

SCORES = []  # in-memory leaderboard (demo); lock because gunicorn uses threads
_lock = threading.Lock()

REQUESTS = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request latency in seconds", ["endpoint"]
)
SCORES_SUBMITTED = Counter("game_scores_submitted_total", "Scores submitted to leaderboard")
HIGH_SCORE = Gauge("game_high_score", "Highest score on the leaderboard")


@app.before_request
def _start_timer():
    g.start = time.perf_counter()


@app.after_request
def _record_and_secure(resp):
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    REQUESTS.labels(request.method, endpoint, resp.status_code).inc()
    if hasattr(g, "start"):
        LATENCY.labels(endpoint).observe(time.perf_counter() - g.start)
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'"
    )
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "no-referrer"
    return resp


@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.get("/health")
def health():
    return jsonify(status="ok", version=VERSION)


@app.get("/api/scores")
def list_scores():
    with _lock:
        return jsonify(list(SCORES))


@app.post("/api/scores")
def submit_score():
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name", "")).strip()
    score = payload.get("score")
    if not NAME_RE.match(name):
        return jsonify(error="name must be 1-12 letters, digits, space, _ or -"), 400
    if isinstance(score, bool) or not isinstance(score, int) or not 0 <= score <= MAX_SCORE:
        return jsonify(error=f"score must be an integer 0-{MAX_SCORE}"), 400
    entry = {"name": name, "score": score}
    with _lock:
        SCORES.append(entry)
        SCORES.sort(key=lambda e: e["score"], reverse=True)
        del SCORES[TOP_N:]
        HIGH_SCORE.set(SCORES[0]["score"])
    SCORES_SUBMITTED.inc()
    return jsonify(entry), 201


@app.get("/api/error")
def trigger_error():
    """Deliberate 500 so you can demo the HighErrorRate alert."""
    return jsonify(error="simulated failure"), 500


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)  # nosec - dev only; prod uses gunicorn
