import json

import pytest

from src.handlers.alert_webhook import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


VALID_ALERT = {
    "alert_id": "alert-test-001",
    "alert_name": "Pod CrashLoopBackOff",
    "severity": "critical",
    "resource_type": "gcp_gke_pod",
    "resource_id": "payment-service-xyz",
    "service_name": "payment-service",
    "timestamp": "2026-06-20T10:00:00Z",
    "metric_name": "container_restart_count",
    "metric_value": 5,
    "labels": {"environment": "prod", "region": "us-central1"},
    "customer_id": "acme-corp",
}


def test_health_returns_200(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = json.loads(resp.data)
    assert data["status"] == "ok"


def test_ingest_valid_alert(client):
    resp = client.post("/alerts/ingest", json=VALID_ALERT)
    assert resp.status_code == 200
    data = json.loads(resp.data)
    assert data["status"] == "accepted"
    assert "trace_id" in data


def test_ingest_missing_required_field(client):
    payload = {k: v for k, v in VALID_ALERT.items() if k != "alert_id"}
    resp = client.post("/alerts/ingest", json=payload)
    assert resp.status_code == 400
    data = json.loads(resp.data)
    assert data["error_code"] == "INVALID_PAYLOAD"


def test_ingest_malformed_json(client):
    resp = client.post("/alerts/ingest", data="not json", content_type="application/json")
    assert resp.status_code == 400


def test_ingest_empty_body(client):
    resp = client.post("/alerts/ingest", content_type="application/json")
    assert resp.status_code == 400
