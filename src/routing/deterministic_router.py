import re
from dataclasses import dataclass
from typing import Optional

from src.state.firestore_client import FirestoreClient
from src.utils.logger import get_logger

logger = get_logger("deterministic_router")


@dataclass
class TeamAssignment:
    team: str
    confidence: float
    rule_matched: str


class DeterministicRouter:
    def __init__(self, firestore_client: FirestoreClient):
        self.fs = firestore_client

    def route_alert(self, alert, customer_id: str) -> TeamAssignment:
        customer = self.fs.get_customer(customer_id)
        if not customer:
            logger.warning("Customer config not found, using fallback", customer_id=customer_id)
            return TeamAssignment(team="platform-infra", confidence=0.0, rule_matched="no-config-fallback")

        rules = customer.get("team_routing_rules", [])

        for rule in rules:
            if self._matches_pattern(alert, rule["pattern"]):
                logger.info(
                    "Alert routed",
                    rule_id=rule["id"],
                    team=rule["assigned_team"],
                    service=alert.service_name,
                )
                return TeamAssignment(
                    team=rule["assigned_team"],
                    confidence=rule.get("confidence", 1.0),
                    rule_matched=rule["id"],
                )

        return TeamAssignment(team="platform-infra", confidence=0.0, rule_matched="fallback")

    def _matches_pattern(self, alert, pattern: str) -> bool:
        if pattern == "*":
            return True
        # "service:payment-*" → match against service_name
        if pattern.startswith("service:"):
            service_pattern = pattern[len("service:"):].replace("*", ".*")
            return bool(re.match(f"^{service_pattern}$", alert.service_name))
        # "category:Database.*" → match against alert_name
        if pattern.startswith("category:"):
            cat_pattern = pattern[len("category:"):].replace("*", ".*")
            return bool(re.match(f"^{cat_pattern}$", alert.alert_name))
        # Plain glob — match against service_name
        regex = pattern.replace("*", ".*")
        return bool(re.match(f"^{regex}$", alert.service_name))
