import hashlib
from datetime import datetime, timezone
from typing import Tuple

from src.state.firestore_client import AlertGroup, FirestoreClient
from src.utils.logger import get_logger

logger = get_logger("idempotency_manager")


class IdempotencyManager:
    def __init__(self, firestore_client: FirestoreClient):
        self.fs = firestore_client

    def get_alert_group_hash(self, service_name: str, alert_type: str, environment: str) -> str:
        content = f"{service_name}|{alert_type}|{environment}"
        return hashlib.md5(content.encode()).hexdigest()

    def process_with_dedup(self, alert) -> Tuple[AlertGroup, bool]:
        """
        Returns (alert_group, is_new).
        is_new=True  → proceed with full LLM pipeline.
        is_new=False → alert is part of ongoing incident, skip LLM.
        """
        alert_type = self._classify_alert_type(alert)
        environment = alert.labels.get("environment", "unknown")
        hash_id = self.get_alert_group_hash(alert.service_name, alert_type, environment)

        alert_group, is_new = self.fs.get_or_create_alert_group(hash_id, alert)

        if not is_new:
            alert_group.occurrence_count += 1
            alert_group.last_occurrence = alert.timestamp

            updates = {
                "occurrence_count": alert_group.occurrence_count,
                "last_occurrence": alert_group.last_occurrence,
            }

            if alert_group.occurrence_count % 5 == 0:
                logger.info(
                    "Alert flapping — recurring occurrence",
                    hash_id=hash_id,
                    count=alert_group.occurrence_count,
                    service=alert.service_name,
                )

            self.fs.update_alert_group(hash_id, updates)

        return alert_group, is_new

    def _classify_alert_type(self, alert) -> str:
        name = alert.alert_name
        if "CrashLoopBackOff" in name:
            return "ContainerCrash"
        if "OOMKilled" in name:
            return "OOMKilled"
        if "HighLatency" in name or "Latency" in name:
            return "HighLatency"
        if "Error" in name or "5xx" in name:
            return "ErrorRate"
        return "Unknown"
