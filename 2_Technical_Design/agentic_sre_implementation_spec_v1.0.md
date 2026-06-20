# Agentic SRE Platform - Implementation Specification v1.0

**Timeline**: 5 weeks | **Team**: 2-3 Engineers | **Status**: Ready to Execute

---

## Week 1: Foundation & Core Components

### Goal
Build the deterministic plumbing: webhook receiver, state management, routing. NO LLM yet.

### Tasks

#### Task 1.1: Project Setup & Infrastructure (All Engineers, 1 day)
**Deliverable**: Running Cloud Run service that can receive webhooks

- [ ] Initialize Python project structure
  ```
  src/
  ├── handlers/
  ├── state/
  ├── routing/
  ├── context/
  ├── agent/
  ├── incidents/
  └── utils/
  ```
- [ ] Set up Cloud Run deployment pipeline (Dockerfile, terraform)
- [ ] Set up Cloud Logging configuration
- [ ] Test: `curl -X POST http://localhost:8080/health` returns 200

**Success Criteria**: 
- Cloud Run service deploys and serves health checks
- Terraform applies without errors
- Logs appear in Cloud Logging

---

#### Task 1.2: Alert Webhook Receiver (Engineer A, 2 days)
**Deliverable**: Receives alerts, validates, normalizes to standard format

**Code Pattern**:
```python
# src/handlers/alert_webhook.py
from flask import Flask, request, jsonify
from pydantic import BaseModel, ValidationError

app = Flask(__name__)

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

@app.route('/alerts/ingest', methods=['POST'])
def ingest_alert():
    try:
        payload = request.json
        alert = AlertPayload(**payload)
        
        # Log and pass to processor
        logger.info(f"Alert received: {alert.alert_id}")
        
        # TODO: Call alert_processor.process(alert)
        
        return jsonify({"status": "accepted", "incident_id": "TBD"}), 200
    except ValidationError as e:
        return jsonify({"error": str(e)}), 400
```

**Tests**:
- [ ] POST with valid payload → 200, returns incident_id
- [ ] POST with missing fields → 400
- [ ] POST with malformed JSON → 400
- [ ] POST with valid payload → logged to Cloud Logging

**Success Criteria**:
- Unit tests pass (100% coverage of webhook handler)
- Can receive a webhook from Postman or curl

---

#### Task 1.3: Firestore State Management (Engineer B, 2 days)
**Deliverable**: Alert groups stored, queried, and updated in Firestore

**Code Pattern**:
```python
# src/state/firestore_client.py
from google.cloud import firestore
from dataclasses import dataclass

@dataclass
class AlertGroup:
    alert_type: str
    service_name: str
    environment: str
    occurrence_count: int = 1
    first_occurrence: str = None
    last_occurrence: str = None
    incident_id: str = None
    state: str = "open"
    assigned_team: str = None
    created_at: str = None
    expires_at: str = None  # TTL

class FirestoreClient:
    def __init__(self, project_id: str):
        self.db = firestore.Client(project=project_id)
    
    def get_or_create_alert_group(self, hash_id: str, alert: AlertPayload) -> tuple[AlertGroup, bool]:
        """
        Returns: (alert_group, is_new)
        """
        existing = self.db.collection("alert_groups").document(hash_id).get()
        
        if existing.exists:
            group = AlertGroup(**existing.to_dict())
            return group, False
        else:
            group = AlertGroup(
                alert_type=alert.alert_name,
                service_name=alert.service_name,
                environment=alert.labels.get("environment", "unknown"),
                first_occurrence=alert.timestamp,
                created_at=datetime.now().isoformat(),
                expires_at=(datetime.now() + timedelta(minutes=60)).isoformat()
            )
            self.db.collection("alert_groups").document(hash_id).set(group.__dict__)
            return group, True
    
    def update_alert_group(self, hash_id: str, updates: dict):
        self.db.collection("alert_groups").document(hash_id).update(updates)
```

**Tests**:
- [ ] Create new alert group → stored in Firestore
- [ ] Query existing alert group → returns correct data
- [ ] Update alert group → occurrence_count incremented
- [ ] TTL deletion → document deleted after 60 min

**Success Criteria**:
- Firestore emulator running for tests
- All CRUD operations tested
- Can inspect Firestore console and see test data

---

#### Task 1.4: Deterministic Router (Engineer A, 2 days)
**Deliverable**: Static YAML-based team routing, no LLM involved

**Code Pattern**:
```python
# src/routing/deterministic_router.py
import re
from dataclasses import dataclass

@dataclass
class TeamAssignment:
    team: str
    confidence: float
    rule_matched: str

class DeterministicRouter:
    def __init__(self, firestore_client):
        self.fs = firestore_client
    
    def route_alert(self, alert: AlertPayload, customer_id: str) -> TeamAssignment:
        # Load customer config from Firestore
        customer = self.fs.db.collection("customers").document(customer_id).get()
        rules = customer.to_dict()["team_routing_rules"]
        
        # Try each rule in order
        for rule in rules:
            if self._matches_pattern(alert, rule["pattern"]):
                return TeamAssignment(
                    team=rule["assigned_team"],
                    confidence=rule.get("confidence", 1.0),
                    rule_matched=rule["id"]
                )
        
        # Should never reach here if config is valid
        raise Exception(f"No routing rule matched for {alert.service_name}")
    
    def _matches_pattern(self, alert: AlertPayload, pattern: str) -> bool:
        # Pattern: "service:payment-*" → matches "payment-"
        # Pattern: "*" → matches anything
        regex_pattern = pattern.replace("*", ".*")
        return re.match(regex_pattern, alert.service_name)

# Example customer config (stored in Firestore):
EXAMPLE_CONFIG = {
    "team_routing_rules": [
        {
            "id": "rule-1",
            "pattern": "service:payment-*",
            "assigned_team": "payment-platform",
            "confidence": 1.0
        },
        {
            "id": "rule-2",
            "pattern": "service:*",
            "assigned_team": "platform-infra",
            "confidence": 0.8
        },
        {
            "id": "fallback",
            "pattern": "*",
            "assigned_team": "on-call",
            "confidence": 0.5
        }
    ]
}
```

**Tests**:
- [ ] Route alert matching rule-1 → "payment-platform"
- [ ] Route alert matching rule-2 → "platform-infra"
- [ ] Route alert matching no specific rule → fallback team
- [ ] Customer config can be updated and re-loaded

**Success Criteria**:
- Routing is deterministic (same alert always gets same team)
- All regex patterns tested
- No LLM involved

---

#### Task 1.5: Alert Idempotency Manager (Engineer B, 1 day)
**Deliverable**: Prevent alert storms by de-duplicating on hash

**Code Pattern**:
```python
# src/state/idempotency_manager.py
import hashlib

class IdempotencyManager:
    def __init__(self, firestore_client):
        self.fs = firestore_client
    
    def get_alert_group_hash(self, service_name: str, alert_type: str, environment: str) -> str:
        """Generate deterministic hash for alert grouping"""
        content = f"{service_name}|{alert_type}|{environment}"
        return hashlib.md5(content.encode()).hexdigest()
    
    def process_with_dedup(self, alert: AlertPayload) -> tuple[AlertGroup, bool]:
        """
        Returns: (alert_group, is_new)
        is_new=True means we should run LLM analysis
        is_new=False means we should skip LLM and just increment counter
        """
        hash_id = self.get_alert_group_hash(
            alert.service_name,
            self._classify_alert_type(alert),
            alert.labels.get("environment", "unknown")
        )
        
        alert_group, is_new = self.fs.get_or_create_alert_group(hash_id, alert)
        
        if not is_new:
            # Recurring alert
            alert_group.occurrence_count += 1
            alert_group.last_occurrence = alert.timestamp
            
            # Update Jira every 5 occurrences
            if alert_group.occurrence_count % 5 == 0:
                logger.info(f"Alert {hash_id} occurred {alert_group.occurrence_count} times")
                # TODO: Update Jira ticket with count
            
            self.fs.update_alert_group(hash_id, alert_group.__dict__)
        
        return alert_group, is_new
    
    def _classify_alert_type(self, alert: AlertPayload) -> str:
        # Map alert names to types
        if "CrashLoopBackOff" in alert.alert_name:
            return "ContainerCrash"
        elif "OOMKilled" in alert.alert_name:
            return "OOMKilled"
        else:
            return "Unknown"
```

**Tests**:
- [ ] First alert creates new group, is_new=True
- [ ] Second identical alert returns existing group, is_new=False
- [ ] occurrence_count increments correctly
- [ ] Different environments create separate groups

**Success Criteria**:
- De-duplication working
- 99% reduction in alerts for flapping scenarios (verified with 50x test alerts)

---

### Week 1 Deliverables
- [ ] Cloud Run service deployed and responding to webhooks
- [ ] Firestore collections created and accessible
- [ ] All 5 components have unit tests (>80% coverage)
- [ ] Can send a test alert via curl and see it processed end-to-end (up to the router step)
- [ ] Logs visible in Cloud Logging with trace IDs
- [ ] Code review completed before moving to Week 2

---

## Week 2: LLM Integration & Incident Creation

### Goal
Add the agentic brain: context aggregation, sanitization, LLM analysis, incident creation.

### Tasks

#### Task 2.1: Context Aggregator (Engineer A, 2 days)
**Deliverable**: Fetch logs, metrics, deployments from GCP APIs

**Code Pattern**:
```python
# src/context/aggregator.py
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3

class ContextAggregator:
    def __init__(self, gcp_project: str):
        self.logging_client = cloud_logging.Client(project=gcp_project)
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        self.gcp_project = gcp_project
    
    def aggregate(self, alert: AlertPayload) -> dict:
        """Fetch all context needed for analysis"""
        
        # Fetch logs (last 30 minutes)
        logs = self._fetch_logs(
            resource_id=alert.resource_id,
            time_window_minutes=30
        )
        
        # Fetch metrics
        metrics = self._fetch_metrics(
            resource_id=alert.resource_id,
            metric_type=alert.metric_name
        )
        
        # Fetch recent deployments
        deployments = self._fetch_deployments(alert.service_name)
        
        return {
            "logs": logs,
            "metrics": metrics,
            "deployments": deployments,
            "alert": alert.__dict__
        }
    
    def _fetch_logs(self, resource_id: str, time_window_minutes: int) -> list:
        """Query Cloud Logging for container logs"""
        filter_str = f"""
        resource.type="k8s_pod"
        AND resource.labels.pod_name="{resource_id}"
        AND timestamp>={datetime.now() - timedelta(minutes=time_window_minutes)}
        """
        
        entries = self.logging_client.list_entries(filter_=filter_str)
        
        logs = []
        for entry in entries:
            logs.append({
                "timestamp": entry.timestamp.isoformat(),
                "severity": entry.severity,
                "message": entry.payload
            })
        
        return logs
    
    def _fetch_metrics(self, resource_id: str, metric_type: str) -> dict:
        # TODO: Use Cloud Monitoring API to fetch time series
        # For MVP, can return dummy data for testing
        return {
            "metric_type": metric_type,
            "datapoints": [
                {"timestamp": "2026-06-04T14:00:00Z", "value": 900},
                {"timestamp": "2026-06-04T14:05:00Z", "value": 1100},
                # ...
            ]
        }
    
    def _fetch_deployments(self, service_name: str) -> list:
        # TODO: Query GCP deployment history
        # For MVP, return dummy data
        return [
            {"version": "v1.45.2", "deployed_at": "2026-06-04T14:18:00Z"},
            {"version": "v1.45.1", "deployed_at": "2026-06-04T10:00:00Z"}
        ]
```

**Tests**:
- [ ] Fetch logs from Cloud Logging (or emulator)
- [ ] Parse and format logs correctly
- [ ] Handle empty results gracefully
- [ ] Respect 30-minute time window

**Success Criteria**:
- All GCP API calls working
- Can inspect aggregated context in test logs
- Metrics data in correct format

---

#### Task 2.2: Context Sanitizer (Engineer B, 2 days)
**Deliverable**: Scrub secrets, truncate to token budget

**Code Pattern**:
```python
# src/context/sanitizer.py
import re

class ContextSanitizer:
    SECRET_PATTERNS = [
        (r'(bearer\s+|authorization:\s*)[\w\-\.]+', r'\1[REDACTED_SECRET]'),
        (r'(api_key|apikey)\s*[=:]\s*[\w\-\.]+', r'\1=[REDACTED_SECRET]'),
        (r'(password|passwd)\s*[=:]\s*[\w\-\.]+', r'\1=[REDACTED_SECRET]'),
        (r'(database_url|db_uri)\s*[=:]\s*[^\s]+', r'\1=[REDACTED_SECRET]'),
        (r'\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b', '[REDACTED_CARD]'),
        (r'\b\d{3}-\d{2}-\d{4}\b', '[REDACTED_SSN]'),
    ]
    
    MAX_LOG_LINES = 100
    MAX_TOKENS = 4000
    TOKENS_PER_WORD = 1.3  # Rough estimate
    
    def sanitize(self, raw_context: dict) -> tuple[dict, str]:
        """
        Sanitize context and return (clean_context, quality_status)
        quality_status: "complete" | "truncated" | "degraded"
        """
        
        # Step 1: Scrub logs
        raw_logs = "\n".join([log["message"] for log in raw_context["logs"]])
        sanitized_logs = self._scrub_secrets(raw_logs)
        
        # Step 2: Truncate lines
        truncated_logs = self._truncate_lines(sanitized_logs, self.MAX_LOG_LINES)
        quality = "truncated" if truncated_logs != sanitized_logs else "complete"
        
        # Step 3: Enforce token budget
        estimated_tokens = self._estimate_tokens(truncated_logs)
        if estimated_tokens > self.MAX_TOKENS:
            truncated_logs = self._truncate_lines(sanitized_logs, 50)
            quality = "degraded"
        
        clean_context = {
            "logs": truncated_logs,
            "metrics": raw_context["metrics"],
            "deployments": raw_context["deployments"],
            "alert": raw_context["alert"]
        }
        
        return clean_context, quality
    
    def _scrub_secrets(self, text: str) -> str:
        """Remove secrets using regex patterns"""
        scrubbed = text
        for pattern, replacement in self.SECRET_PATTERNS:
            scrubbed = re.sub(pattern, replacement, scrubbed, flags=re.IGNORECASE)
        return scrubbed
    
    def _truncate_lines(self, text: str, max_lines: int) -> str:
        """Keep only last N lines"""
        lines = text.splitlines()
        if len(lines) > max_lines:
            lines = lines[-max_lines:]
            lines.insert(0, f"[TRUNCATED] Showing last {max_lines} of original lines.")
        return "\n".join(lines)
    
    def _estimate_tokens(self, text: str) -> int:
        """Estimate token count"""
        word_count = len(text.split())
        return int(word_count * self.TOKENS_PER_WORD)
```

**Tests**:
- [ ] Scrub API keys correctly
- [ ] Scrub passwords and database URLs
- [ ] Scrub credit card numbers and SSNs
- [ ] Truncate to 100 lines
- [ ] Enforce 4K token limit
- [ ] Preserve log meaning after scrubbing

**Success Criteria**:
- No secrets in sanitized output
- Token estimates accurate to within ±20%
- All regex patterns tested with real log samples

---

#### Task 2.3: LLM Agent Integration (Engineer A, 2 days)
**Deliverable**: Call Claude/Gemini API, parse response, validate structure

**Code Pattern**:
```python
# src/agent/llm_orchestrator.py
from anthropic import Anthropic

class LLMAgentOrchestrator:
    def __init__(self, model: str = "claude-sonnet-4-6"):
        self.model = model
        self.client = Anthropic()
    
    def analyze(self, context: dict, alert: AlertPayload) -> dict:
        """
        Send context to LLM, get RCA + recommendations
        """
        
        system_prompt = """
You are an expert SRE analyzing pod crashes.

RULES:
1. Base conclusions ONLY on provided logs and metrics.
2. Do NOT infer without evidence.
3. Provide 2-3 actionable recommendations.
4. Include confidence (0-1) for your analysis.
5. Output ONLY valid JSON, no markdown.

Response format:
{
    "root_cause": "string",
    "confidence": 0.8,
    "contributing_factors": ["string"],
    "recommendations": [
        {"priority": 1, "action": "string", "rationale": "string", "effort": "low|medium|high"}
    ]
}
        """
        
        user_message = self._format_user_message(context, alert)
        
        try:
            response = self.client.messages.create(
                model=self.model,
                max_tokens=2000,
                system=system_prompt,
                messages=[{"role": "user", "content": user_message}]
            )
            
            # Parse response
            analysis = self._parse_response(response.content[0].text)
            
            # Validate
            self._validate_analysis(analysis)
            
            return analysis
            
        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            raise
    
    def _format_user_message(self, context: dict, alert: AlertPayload) -> str:
        return f"""
Service: {alert.service_name}
Alert: {alert.alert_name}
Severity: {alert.severity}

Recent logs:
{context['logs']}

Metrics:
{context['metrics']}

Recent deployments:
{context['deployments']}

Analyze the crash and provide RCA + recommendations.
        """
    
    def _parse_response(self, response_text: str) -> dict:
        """Parse JSON response from LLM"""
        import json
        return json.loads(response_text)
    
    def _validate_analysis(self, analysis: dict):
        """Ensure response has required fields"""
        required = ["root_cause", "confidence", "recommendations"]
        for field in required:
            assert field in analysis, f"Missing field: {field}"
        assert 0 <= analysis["confidence"] <= 1, "Confidence must be 0-1"
        assert len(analysis["recommendations"]) > 0, "Need at least 1 recommendation"
```

**Tests**:
- [ ] Call Claude API with sample context
- [ ] Parse JSON response correctly
- [ ] Validate required fields
- [ ] Handle API errors gracefully
- [ ] Benchmark latency and cost

**Success Criteria**:
- P95 latency < 5 seconds
- Average cost < $0.05 per analysis
- All responses have valid JSON structure

---

#### Task 2.4: Jira Incident Creator (Engineer B, 2 days)
**Deliverable**: Create Jira tickets with analysis, fallback to Cloud Tasks

**Code Pattern**:
```python
# src/incidents/incident_creator.py
from jira import JIRA

class IncidentCreator:
    def __init__(self, firestore_client):
        self.fs = firestore_client
        # TODO: Load Jira credentials from Firestore
    
    def create_incident(self, analysis: dict, alert_group, alert: AlertPayload, customer_id: str) -> str:
        """
        Create Jira ticket, fallback to Cloud Tasks if Jira fails
        Returns: incident_id
        """
        
        try:
            # Try primary path: Jira API
            ticket = self._create_jira_ticket(analysis, alert_group, alert, customer_id)
            incident_id = ticket.key
            jira_url = f"https://jira.company.com/browse/{ticket.key}"
            
        except Exception as e:
            logger.error(f"Jira API failed: {e}. Using Cloud Tasks fallback.")
            # Fallback: Queue to Cloud Tasks
            incident_id = self._queue_to_cloud_tasks(analysis, alert_group, customer_id)
            jira_url = None
        
        # Store in Firestore
        incident_record = {
            "incident_id": incident_id,
            "jira_url": jira_url,
            "analysis": analysis,
            "alert_group_id": alert_group.id,
            "created_at": datetime.now().isoformat()
        }
        self.fs.db.collection("incidents").document(incident_id).set(incident_record)
        
        # Update alert group
        self.fs.update_alert_group(alert_group.id, {
            "incident_id": incident_id,
            "incident_created": True
        })
        
        return incident_id
    
    def _create_jira_ticket(self, analysis: dict, alert_group, alert: AlertPayload, customer_id: str):
        """Create ticket in Jira"""
        
        # Load customer Jira credentials from Firestore
        customer = self.fs.db.collection("customers").document(customer_id).get()
        jira_token = customer.to_dict()["credentials"]["jira_api_token"]
        
        jira = JIRA(
            "https://jira.company.com",
            basic_auth=("user@company.com", jira_token)
        )
        
        description = self._format_description(analysis, alert_group, alert)
        
        issue_dict = {
            "project": {"key": "INFRA"},
            "issuetype": {"name": "Incident"},
            "summary": f"[{alert_group.severity.upper()}] {alert.service_name} - {analysis['root_cause'][:50]}",
            "description": description,
            "priority": {"name": self._map_severity_to_priority(alert_group.severity)},
            "labels": ["agentic-sre", alert.service_name]
        }
        
        issue = jira.create_issue(fields=issue_dict)
        return issue
    
    def _format_description(self, analysis: dict, alert_group, alert: AlertPayload) -> str:
        return f"""
*Service*: {alert.service_name}
*Severity*: {alert_group.severity}
*Analysis Confidence*: {analysis['confidence']*100:.0f}%

h3. Root Cause
{analysis['root_cause']}

h3. Contributing Factors
{chr(10).join([f'* {f}' for f in analysis['contributing_factors']])}

h3. Recommendations
{chr(10).join([
    f"{r['priority']}. [{r['effort'].upper()}] {r['action']} - {r['rationale']}"
    for r in analysis['recommendations']
])}

_Generated by Agentic SRE Platform_
        """
    
    def _queue_to_cloud_tasks(self, analysis: dict, alert_group, customer_id: str) -> str:
        """Queue incident to Cloud Tasks if Jira fails"""
        # TODO: Implement Cloud Tasks queue
        incident_id = f"queued-{uuid4()}"
        logger.info(f"Incident queued to Cloud Tasks: {incident_id}")
        return incident_id
```

**Tests**:
- [ ] Create Jira ticket with analysis
- [ ] Verify ticket has correct summary, description, labels
- [ ] Fallback to Cloud Tasks when Jira API fails
- [ ] Update alert_group with incident_id

**Success Criteria**:
- Can create Jira tickets with real account (sandbox)
- Fallback path works (Cloud Tasks)
- All fields populated correctly

---

### Week 2 Deliverables
- [ ] Context aggregator fetching logs, metrics, deployments
- [ ] Sanitizer removing secrets and truncating to token budget
- [ ] LLM integration working with Claude (or Gemini if benchmarking)
- [ ] Jira tickets created with incident details
- [ ] End-to-end test: Alert → Analysis → Jira ticket
- [ ] All unit tests passing
- [ ] Cost/latency benchmarks recorded

---

## Week 3: Testing, Demo Prep, Early Validation

### Goal
Polish MVP, create demo scenario, prepare for early customer.

### Tasks

#### Task 3.1: Create Demo Scenario (All Engineers, 2 days)
**Deliverable**: Intentional pod crash on GCP GKE, captured logs, full end-to-end demo

**Steps**:
- [ ] Deploy test service to GCP GKE
- [ ] Intentionally create OOMKill scenario
- [ ] Capture logs and metrics
- [ ] Walk through full pipeline manually
- [ ] Record demo video (5 min)
- [ ] Document demo runbook

**Demo Script**:
```
1. Show alert coming in (webhook)
2. Show Firestore: new alert_group created
3. Show Cloud Logging: analysis in progress
4. Show Cloud Logging: context being gathered
5. Show Cloud Logging: LLM being called
6. Show Jira: ticket created with RCA + recommendations
7. Point to GCP logs link in Jira ticket
8. Explain: "Without this agent, L1 would spend 20+ minutes on triage"
```

---

#### Task 3.2: Benchmarking (Engineer A, 2 days)
**Deliverable**: Claude vs Gemini 2.5 Pro comparison, decision made

**Benchmarks to Run**:
```
Run 100 sample incidents through both models:
- Accuracy (team assignment)
- Cost (tokens used, $/incident)
- Latency (P50, P95, P99)
- Hallucination rate (false causes)
```

**Example Results Table**:
```
| Metric | Claude Sonnet | Gemini 2.5 Pro | Winner |
|--------|---------------|----------------|---------|
| Accuracy | 0.92 | 0.88 | Claude |
| Cost/incident | $0.08 | $0.04 | Gemini |
| P95 Latency | 2.8s | 3.5s | Claude |
| Hallucinations | 2/100 | 5/100 | Claude |
```

**Decision Logic**:
- If Claude is better on majority (3/4), use Claude
- If Gemini is better, calculate ROI of cost savings vs accuracy loss
- Document decision in DECISION_LOG.md

---

#### Task 3.3: Telemetry Dashboard (Engineer B, 2 days)
**Deliverable**: Cloud Logging dashboard showing key metrics

**Metrics to Display**:
- [ ] Alert ingestion rate (alerts/min)
- [ ] Incident creation rate (incidents/min)
- [ ] De-duplication effectiveness (% alerts skipped)
- [ ] LLM accuracy (team assignment correctness)
- [ ] P50/P95 latency (alert to ticket)
- [ ] Error rate (% failures)
- [ ] Cost ($/incident)

**Dashboard Query Example**:
```sql
# Alert ingestion rate
SELECT
  COUNT(*) as alert_count,
  TIMESTAMP_TRUNC(timestamp, MINUTE) as minute
FROM `project.dataset.audit_logs`
WHERE action = "alert_received"
GROUP BY minute
ORDER BY minute DESC
```

---

### Week 3 Deliverables
- [ ] Demo scenario working end-to-end
- [ ] Claude vs Gemini benchmarking complete, winner selected
- [ ] Telemetry dashboard deployed
- [ ] Demo video recorded and narrated
- [ ] All edge cases documented in runbook
- [ ] Ready to onboard first customer

---

## Week 4: Staging & Early Customer Onboarding

### Goal
Deploy to production staging, onboard early customer, collect real-world feedback.

### Tasks

#### Task 4.1: Staging Deployment (Engineer A, 1 day)
**Deliverable**: Production-grade Cloud Run, Firestore, monitoring

**Checklist**:
- [ ] Run production terraform
- [ ] Enable Cloud Audit Logging
- [ ] Set up Cloud Monitoring alerts (latency, errors)
- [ ] Set up on-call rotation
- [ ] Document runbook for on-call engineer
- [ ] Run "break glass" failover test (Cloud Run down → Pub/Sub)

---

#### Task 4.2: Customer Onboarding (Engineer B, 2 days)
**Deliverable**: First customer configured and running

**Onboarding Checklist**:
- [ ] Customer creates GitHub App (scoped to repo)
- [ ] Customer provides Jira API token (create-only)
- [ ] Customer defines team routing rules (YAML)
- [ ] Customer sets Pub/Sub fallback topic
- [ ] We set up Firestore customer record
- [ ] Customer tests webhook (curl)
- [ ] Run first incident end-to-end with customer
- [ ] Collect feedback

**Customer Feedback Questions**:
- Was the Jira ticket useful?
- Did team assignment routing work?
- Any false positives/negatives?
- Would you have changed any recommendations?
- What's the value vs. manual triage?

---

#### Task 4.3: Incident Response & Tuning (All Engineers, 2 days)
**Deliverable**: First customer incidents handled, system tuned

**Activities**:
- [ ] Monitor first incidents live
- [ ] Respond to any customer issues
- [ ] Tune truncation/sanitization based on real logs
- [ ] Adjust LLM system prompt if needed
- [ ] Update team routing rules as needed
- [ ] Document edge cases (e.g., "crash with no stack trace")

---

### Week 4 Deliverables
- [ ] Production staging environment running
- [ ] First customer onboarded
- [ ] 10+ real incidents processed
- [ ] Customer feedback collected
- [ ] System stable (>99% uptime)
- [ ] Ready for Phase 2 roadmap

---

## Week 5: Refinement & Phase 2 Planning

### Goal
Wrap up MVP, document lessons, plan Phase 2.

### Tasks

#### Task 5.1: Documentation & Runbooks (Engineer B, 2 days)
**Deliverable**: Complete runbook for on-call and new customers

**Documents to Create**:
- [ ] Operator Runbook (how to debug alerts)
- [ ] Customer Onboarding Guide (step-by-step)
- [ ] GitHub App Setup Guide
- [ ] FAQ & Troubleshooting
- [ ] Known Limitations & Future Work

---

#### Task 5.2: Retrospective & Phase 2 Planning (All Engineers, 1 day)
**Deliverable**: Retrospective notes, Phase 2 roadmap

**Retrospective Questions**:
- What worked well?
- What was harder than expected?
- What surprised us?
- What should we do differently?

**Phase 2 Planning** (separate document):
- [ ] Multi-cloud support (AWS/Azure)
- [ ] Additional incident types (latency, errors, etc.)
- [ ] RAG/embeddings for source code
- [ ] Autonomous remediation (with human approval)
- [ ] Customer feedback loops

---

### Week 5 Deliverables
- [ ] Complete documentation set
- [ ] Retrospective meeting notes
- [ ] Phase 2 roadmap document
- [ ] MVP "done"

---

## Success Criteria Checklist

### By End of Week 1
- [ ] Cloud Run service deployed and receiving webhooks
- [ ] Firestore state management working
- [ ] Deterministic routing rules engine working
- [ ] De-duplication preventing alert storms (99% reduction)
- [ ] All code reviewed, >80% test coverage

### By End of Week 2
- [ ] End-to-end pipeline: Alert → Jira ticket
- [ ] Context sanitization removing all secrets
- [ ] LLM (Claude or Gemini) generating RCAs
- [ ] Benchmarking complete, LLM selected
- [ ] All tests passing, production-ready code

### By End of Week 3
- [ ] Demo scenario working perfectly
- [ ] Telemetry dashboard showing real metrics
- [ ] Runbook complete
- [ ] Team comfortable with architecture

### By End of Week 4
- [ ] First customer onboarded and running
- [ ] 10+ incidents processed successfully
- [ ] Team assignment accuracy >85%
- [ ] MTTR reduced (measured with customer)
- [ ] Zero critical bugs found

### By End of Week 5
- [ ] Documentation complete
- [ ] Retrospective completed
- [ ] Phase 2 roadmap ready
- [ ] Ready to scale to 5+ customers

---

## Daily Standup Template

Each day, each engineer reports:

```
Yesterday:
- [Task completed]
- [Blockers resolved]

Today:
- [Task starting]
- [Expected completion]

Blockers:
- [Any blockers for team help]

Metrics:
- Lines of code written
- Tests written
- Code review PRs
```

---

## Approval Sign-Off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Engineering Lead | [TBD] | | |
| Product Owner | [TBD] | | |
| SRE Lead | [TBD] | | |

---

**Ready to execute. All pieces in place. Let's build this.**

