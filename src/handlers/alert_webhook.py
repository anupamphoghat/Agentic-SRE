import os

from flask import Flask, jsonify, request
from pydantic import BaseModel, ValidationError

from src.utils.logger import generate_trace_id, get_logger

app = Flask(__name__)
logger = get_logger("alert_webhook")


class AlertPayload(BaseModel):
    alert_id: str
    alert_name: str
    severity: str  # "critical" | "warning" | "info"
    resource_type: str
    resource_id: str
    service_name: str
    timestamp: str  # RFC3339
    metric_name: str
    metric_value: float
    labels: dict
    source_system: str = "unknown"
    customer_id: str = "default"


@app.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "ok", "service": "agentic-sre-agent"}), 200


@app.route("/alerts/ingest", methods=["POST"])
def ingest_alert():
    trace_id = generate_trace_id()

    try:
        try:
            payload = request.get_json(force=True, silent=True)
        except Exception:
            payload = None

        if payload is None:
            return jsonify({"status": "error", "error_code": "INVALID_PAYLOAD", "trace_id": trace_id}), 400

        alert = AlertPayload(**payload)

        logger.info(
            "Alert received",
            trace_id=trace_id,
            alert_id=alert.alert_id,
            service_name=alert.service_name,
            alert_severity=alert.severity,
            customer_id=alert.customer_id,
        )

        # Pipeline will be wired up in subsequent weeks
        return jsonify({"status": "accepted", "incident_id": "TBD", "trace_id": trace_id}), 200

    except ValidationError as e:
        logger.error("Payload validation failed", trace_id=trace_id, error=str(e))
        return jsonify({"status": "error", "error_code": "INVALID_PAYLOAD", "error_message": str(e), "trace_id": trace_id}), 400

    except Exception as e:
        logger.error("Unexpected error", trace_id=trace_id, error=str(e))
        return jsonify({"status": "error", "error_code": "INTERNAL_ERROR", "trace_id": trace_id}), 500
