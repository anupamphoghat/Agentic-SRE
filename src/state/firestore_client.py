import os
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple

from google.cloud import firestore

from src.utils.logger import get_logger

logger = get_logger("firestore_client")


@dataclass
class AlertGroup:
    alert_type: str
    service_name: str
    environment: str
    occurrence_count: int = 1
    first_occurrence: Optional[str] = None
    last_occurrence: Optional[str] = None
    incident_id: Optional[str] = None
    incident_created: bool = False
    state: str = "open"
    assigned_team: Optional[str] = None
    severity: str = "unknown"
    customer_id: str = "default"
    created_at: Optional[str] = None
    # expires_at is the TTL field — must be a Firestore Timestamp for the TTL policy to fire
    expires_at: Optional[str] = None


class FirestoreClient:
    def __init__(self, project_id: str, database: str = "agentic-sre-db"):
        self.db = firestore.Client(project=project_id, database=database)

    def get_or_create_alert_group(self, hash_id: str, alert) -> Tuple[AlertGroup, bool]:
        ref = self.db.collection("alert_groups").document(hash_id)
        doc = ref.get()

        if doc.exists:
            group = AlertGroup(**{k: v for k, v in doc.to_dict().items() if k in AlertGroup.__dataclass_fields__})
            return group, False

        now = datetime.now(timezone.utc)
        group = AlertGroup(
            alert_type=alert.alert_name,
            service_name=alert.service_name,
            environment=alert.labels.get("environment", "unknown"),
            severity=alert.severity,
            customer_id=alert.customer_id,
            first_occurrence=alert.timestamp,
            last_occurrence=alert.timestamp,
            created_at=now.isoformat(),
            expires_at=(now + timedelta(minutes=60)).isoformat(),
        )
        ref.set(asdict(group))
        logger.info("Alert group created", hash_id=hash_id, service=alert.service_name)
        return group, True

    def update_alert_group(self, hash_id: str, updates: dict) -> None:
        self.db.collection("alert_groups").document(hash_id).update(updates)

    def get_customer(self, customer_id: str) -> Optional[dict]:
        doc = self.db.collection("customers").document(customer_id).get()
        return doc.to_dict() if doc.exists else None

    def create_incident(self, incident_id: str, data: dict) -> None:
        self.db.collection("incidents").document(incident_id).set(data)
