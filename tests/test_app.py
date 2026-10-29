import pytest

from app.app import SCORES, app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    SCORES.clear()
    return app.test_client()


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_game_page_served(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert b"Snake" in resp.data
    assert client.get("/static/game.js").status_code == 200


def test_security_headers(client):
    headers = client.get("/").headers
    assert "default-src 'self'" in headers["Content-Security-Policy"]
    assert headers["X-Content-Type-Options"] == "nosniff"
    assert headers["X-Frame-Options"] == "DENY"


def test_leaderboard_sorted_and_stored(client):
    client.post("/api/scores", json={"name": "ann", "score": 30})
    client.post("/api/scores", json={"name": "bob", "score": 90})
    scores = client.get("/api/scores").get_json()
    assert [s["name"] for s in scores] == ["bob", "ann"]


def test_leaderboard_capped_at_ten(client):
    for i in range(15):
        client.post("/api/scores", json={"name": f"p{i}", "score": i * 10})
    scores = client.get("/api/scores").get_json()
    assert len(scores) == 10
    assert scores[0]["score"] == 140


@pytest.mark.parametrize(
    "payload",
    [
        {"name": "", "score": 10},
        {"name": "<script>", "score": 10},
        {"name": "ok", "score": -1},
        {"name": "ok", "score": 10**6},
        {"name": "ok", "score": "10"},
        {"name": "ok", "score": True},
        {},
    ],
)
def test_invalid_scores_rejected(client, payload):
    assert client.post("/api/scores", json=payload).status_code == 400


def test_metrics_exposed(client):
    client.post("/api/scores", json={"name": "ann", "score": 10})
    body = client.get("/metrics").get_data(as_text=True)
    assert "http_requests_total" in body
    assert "game_scores_submitted_total" in body
    assert "game_high_score" in body
