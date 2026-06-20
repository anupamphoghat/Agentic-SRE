# Agentic SRE Platform - Technical Design Document (TDD) v1.0

**Document Version**: 1.0  
**Date**: June 2026  
**Status**: Ready for Implementation  
**Team**: 2-3 Engineers, 5-week MVP timeline

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Models & Schemas](#data-models--schemas)
3. [API Contracts](#api-contracts)
4. [Component Design](#component-design)
5. [Reference Implementations](#reference-implementations)
6. [Error Handling & Recovery](#error-handling--recovery)
7. [Deployment Architecture](#deployment-architecture)

---

## Architecture Overview

### System Topology (Complete Flow)

```
┌─────────────────────────────────────────────────────────────────┐
│ Customer Alert System (Prometheus/Datadog/GCP Monitoring)       │
└──────────────────────┬──────────────────────────────────────────┘
                       │ Alert Webhook
                       ▼
        ┌──────────────────────────────────┐
        │  GCP Pub/Sub Topic (Fallback)    │ ← Emergency Buffer
        └──────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        ▼                             ▼
    ┌────────────────────────┐  ┌──────────────────┐
    │  Cloud Run Container   │  │  (If CR down,    │
    │  (Primary Path)        │  │   messages queue │
    │                        │  │   here)          │
    └────────────────────────┘  └──────────────────┘
             │
             ├─ Alert Webhook Receiver
             │  (Normalize payload)
             │
             ├─ Idempotency Layer (Firestore)
             │  (Check: exists alert_group[hash]?)
             │
             ├─ Deterministic Router
             │  (Apply static regex rules)
             │
             ├─ Context Aggregator
             │  (Fetch logs, metrics, deployments)
             │
             ├─ Sanitizer Layer
             │  (Scrub secrets, truncate to 4K tokens)
             │
             ├─ LLM Agent (Claude or Gemini)
             │  (Generate RCA + recommendations)
             │
             ├─ Incident Creator
             │  (Create Jira ticket)
             │
             └─ Audit Logger (Cloud Logging)
                (Log all decisions)
```

### Key Design Principles

1. **Layered Architecture**: Each layer has a single responsibility
2. **Fail-Open**: If any layer fails, gracefully degrade (don't lose alerts)
3. **Deterministic Before Agentic**: Business logic handled by deterministic code, not LLM
4. **Security-First**: Sanitization happens BEFORE any external API call
5. **Observable**: Every decision logged, traceable, auditable

---

## Data Models & Schemas

### 1. Alert Payload (Normalized)

**Input Format** (from customer's alert system):
```json
{
  "alert_id": "alert-20260604-001",
  "alert_name": "Pod CrashLoopBackOff",
  "severity": "critical",
  "resource_type": "gcp_gke_pod",
  "resource_id": "payment-service-xyz-abc",
  "service_name": "payment-service",
  "timestamp": "2026-06-04T14:23:45Z",
  "metric_name": "container_restart_count",
  "metric_value": 5,
  "labels": {
    "environment": "prod",
    "region": "us-central1",
    "namespace": "default"
  },
  "source_system": "gcp_monitoring"
}
```

**Firestore Collection**: `alerts_raw`
```
Document ID: "alert-20260604-001"
{
  "payload": {...},
  "received_at": "2026-06-04T14:23:45Z",
  "processing_status": "pending|processing|complete|failed",
  "alert_group_id": "payment-service|ContainerCrash|prod"
}
```

### 2. Alert Group (De-Duplication State)

**Firestore Collection**: `alert_groups`

```
Document ID: HASH(service_name + alert_type + environment)
Example: "payment-service|ContainerCrash|prod"

{
  "alert_type": "ContainerCrash",
  "service_name": "payment-service",
  "environment": "prod",
  "resource_type": "gcp_gke_pod",
  
  // Temporal tracking
  "first_occurrence": "2026-06-04T14:23:45Z",
  "last_occurrence": "2026-06-04T14:24:30Z",
  "occurrence_count": 47,
  
  // Incident reference
  "incident_created": true,
  "incident_id": "inc-20260604-001",
  "jira_ticket_url": "https://jira.company.com/INFRA-1234",
  
  // State machine
  "state": "open",  // or "resolved", "escalated"
  "state_changed_at": "2026-06-04T14:23:45Z",
  
  // Analysis tracking
  "last_analysis_timestamp": "2026-06-04T14:23:50Z",
  "last_analysis_confidence": 0.92,
  "last_recommendation_action": "increase_memory_limit",
  
  // Lifecycle
  "created_at": "2026-06-04T14:23:45Z",
  "expires_at": "2026-06-04T15:23:45Z",  // TTL: 60 minutes
  "ttl_seconds": 3600,
  
  // Metadata
  "assigned_team": "platform-infra",
  "severity": "critical",
  "customer_id": "acme-corp"
}
```

**TTL Cleanup**: Firestore TTL policy deletes documents after 60 minutes of silence.

### 3. Customer Configuration

**Firestore Collection**: `customers`

```
Document ID: "acme-corp"

{
  "customer_id": "acme-corp",
  "name": "Acme Corporation",
  "created_at": "2026-06-01T10:00:00Z",
  
  // GCP Configuration
  "gcp_project_id": "acme-prod",
  "gcp_region": "us-central1",
  
  // Authentication
  "credentials": {
    "jira_api_token": "[ENCRYPTED_AES256]",
    "github_app_id": "123456",
    "github_app_private_key": "[ENCRYPTED_AES256]",
    "github_installation_id": "789012"
  },
  
  // GitHub Permissions
  "allowed_github_repos": [
    "acme-corp/payment-service",
    "acme-corp/auth-service"
  ],
  
  // Incident Routing Configuration
  "team_routing_rules": [
    {
      "id": "rule-001",
      "pattern": "service:payment-*",
      "assigned_team": "payment-platform",
      "confidence": 1.0
    },
    {
      "id": "rule-002",
      "pattern": "category:Database.*",
      "assigned_team": "data-infrastructure",
      "confidence": 1.0
    },
    {
      "id": "rule-003",
      "pattern": "*",  // Fallback
      "assigned_team": "platform-infra",
      "confidence": 0.5
    }
  ],
  
  // Incident Categories
  "incident_categories": [
    {
      "id": "Infrastructure.Compute.ContainerCrash",
      "keywords": ["CrashLoopBackOff", "OOMKilled", "exit_code_1"],
      "assigned_team": "platform-infra",
      "severity_default": "warning"
    }
  ],
  
  // Feature Flags
  "features": {
    "fetch_source_code": true,
    "fetch_recent_commits": true,
    "analyze_memory_trends": true,
    "send_slack_notifications": false
  },
  
  // SLO Configuration
  "slos": {
    "critical_alert_response_time_seconds": 30,
    "warning_alert_response_time_seconds": 300,
    "team_assignment_accuracy_target": 0.85
  }
}
```

### 4. Incident Report (Output)

**Firestore Collection**: `incidents`

```
Document ID: "inc-20260604-001"

{
  "incident_id": "inc-20260604-001",
  "customer_id": "acme-corp",
  "alert_group_id": "payment-service|ContainerCrash|prod",
  
  // Classification
  "classification": {
    "category": "Infrastructure.Compute.ContainerCrash",
    "subcategory": "OOMKilled",
    "severity": "critical",
    "assigned_team": "platform-infra",
    "confidence": 0.92
  },
  
  // Analysis
  "analysis": {
    "root_cause": "Container memory limit exceeded. Service consuming 2.1GB against 2GB limit after deployment v1.45.2",
    "contributing_factors": [
      "Memory leak in new version (v1.45.2) introduced in commit abc123",
      "Traffic spike 2x normal detected 15min before crash"
    ],
    "confidence_score": 0.92
  },
  
  // Recommendations
  "recommendations": [
    {
      "priority": 1,
      "action": "Increase memory limit to 3GB",
      "rationale": "Stop OOMKill errors immediately while investigating",
      "risks": "May mask underlying memory leak if not fixed in parallel",
      "effort": "low",
      "estimated_mttr_reduction_minutes": 5
    },
    {
      "priority": 2,
      "action": "Investigate memory leak in v1.45.2",
      "rationale": "Linear memory growth suggests leak, not spike",
      "effort": "medium",
      "estimated_mttr_reduction_minutes": 30
    }
  ],
  
  // Evidence & Context
  "evidence": {
    "logs_sample": "2026-06-04T14:23:40Z ERROR Cannot allocate memory in pool_allocator.rs:234",
    "deployment_correlation": {
      "deployed_version": "v1.45.2",
      "deployment_timestamp": "2026-06-04T14:18:30Z",
      "time_delta_seconds": 315
    },
    "metrics": {
      "memory_baseline_v1_44_1": "900MB avg, 1.1GB peak",
      "memory_current_v1_45_2": "linear growth from 1.2GB to 2.1GB over 20 minutes",
      "pattern": "consistent leak, not spike"
    }
  },
  
  // Context Quality
  "context_quality": {
    "status": "complete",  // or "truncated", "degraded"
    "logs_truncated": false,
    "source_code_fetched": true,
    "source_code_files": ["pool_allocator.rs"],
    "sanitization_warnings": []
  },
  
  // Links
  "links": {
    "gcp_logs": "https://console.cloud.google.com/logs/query?project=acme-prod&query=...",
    "gcp_metrics": "https://console.cloud.google.com/monitoring/dashboards/custom/...",
    "github_commit": "https://github.com/acme-corp/payment-service/commit/abc123def456",
    "jira_ticket": "https://jira.acme-corp.com/INFRA-1234"
  },
  
  // Metadata
  "llm_model_used": "claude-sonnet-4-6",
  "analysis_timestamp": "2026-06-04T14:23:55Z",
  "analysis_duration_seconds": 3.2,
  "tokens_used": {
    "input": 2400,
    "output": 600,
    "total": 3000
  },
  "created_at": "2026-06-04T14:23:45Z",
  "updated_at": "2026-06-04T14:23:55Z"
}
```

### 5. Audit Log (Cloud Logging)

Each action logged to Cloud Logging with structured format:

```json
{
  "timestamp": "2026-06-04T14:23:45.123Z",
  "severity": "INFO",
  "incident_id": "inc-20260604-001",
  "customer_id": "acme-corp",
  "action": "alert_received",
  "details": {
    "alert_id": "alert-20260604-001",
    "alert_group_hash": "payment-service|ContainerCrash|prod",
    "is_new_group": true,
    "processing_path": "primary_webhook"
  },
  "trace_id": "5e3b8e3c-4f2a-11eb-ae93-0242ac110002"
}
```

---

## API Contracts

### 1. Alert Webhook Endpoint

**Endpoint**: `POST /alerts/ingest`

**Request**:
```json
{
  "alert_id": "string (required)",
  "alert_name": "string (required)",
  "severity": "critical | warning | info",
  "resource_type": "gcp_gke_pod | gcp_cloud_run | vm_instance",
  "resource_id": "string (required)",
  "service_name": "string (required)",
  "timestamp": "RFC3339 (required)",
  "metric_name": "string (required)",
  "metric_value": "number (required)",
  "labels": {
    "environment": "prod | staging | dev",
    "region": "string",
    "namespace": "string"
  }
}
```

**Response (Success)**:
```json
{
  "status": "accepted",
  "incident_id": "inc-20260604-001",
  "processing_mode": "sync | async | buffered",
  "trace_id": "5e3b8e3c-4f2a-11eb-ae93-0242ac110002"
}
```

**Response (Failure)**:
```json
{
  "status": "error",
  "error_code": "INVALID_PAYLOAD | RATE_LIMITED | INTERNAL_ERROR",
  "error_message": "string",
  "trace_id": "string"
}
```

**HTTP Status Codes**:
- `200 OK`: Alert accepted (sync or async processing)
- `202 Accepted`: Alert queued for later processing
- `400 Bad Request`: Invalid payload
- `429 Too Many Requests`: Rate limited, try again later
- `503 Service Unavailable`: Platform overloaded, use Pub/Sub fallback
- `500 Internal Server Error`: Unexpected error, check logs

### 2. Internal Tool APIs (Agent-Facing)

**Tool: query_gcp_logs**
```python
def query_gcp_logs(
    resource_type: str,  # "gcp_gke_pod" | "gcp_cloud_run"
    resource_id: str,
    time_window_minutes: int = 30,  # max 60
    filter_expr: str = None
) -> LogQueryResponse:
    """
    Query GCP Cloud Logging for container logs.
    
    Returns:
        {
            "logs": [{"timestamp": "", "severity": "", "message": ""}],
            "log_count": int,
            "truncated": bool,
            "estimated_tokens": int
        }
    """
```

**Tool: query_gcp_metrics**
```python
def query_gcp_metrics(
    metric_type: str,  # "memory_usage" | "cpu_usage" | "restart_count"
    resource_id: str,
    time_window_minutes: int = 30
) -> MetricsQueryResponse:
    """
    Query GCP Cloud Monitoring for time series data.
    
    Returns:
        {
            "metric_name": str,
            "datapoints": [{"timestamp": "", "value": float}],
            "baseline_avg": float,
            "current_avg": float,
            "trend": "increasing" | "decreasing" | "stable"
        }
    """
```

**Tool: fetch_source_code**
```python
def fetch_source_code(
    repo: str,  # "acme-corp/payment-service"
    file_paths: List[str],  # ["src/main.go", "src/allocator.rs"]
    context_lines: int = 10  # lines before/after error line
) -> SourceCodeResponse:
    """
    Fetch source code files.
    STRICT CONSTRAINTS:
    - Only allows files extracted from stack traces
    - Max 3 files, 200 lines per file, 1500 tokens total
    - Validates against whitelist/blacklist
    
    Returns:
        {
            "files": [{"path": "", "content": "", "error_line": int}],
            "total_lines": int,
            "total_tokens": int,
            "validation_warnings": []
        }
    """
```

---

## Component Design

### Component 1: Alert Webhook Receiver

**Location**: `src/handlers/alert_webhook.py`

**Responsibilities**:
1. Receive HTTP POST with alert payload
2. Validate JSON schema
3. Normalize to standard AlertPayload format
4. Assign processing mode (sync/async/buffered)
5. Pass to idempotency layer

**Pseudocode**:
```python
class AlertWebhookHandler:
    def handle_post(self, request: Request) -> Response:
        try:
            # Parse JSON
            payload = request.json()
            
            # Validate schema
            alert = AlertPayload.from_dict(payload)
            
            # Log receipt
            logger.info(f"Alert received: {alert.alert_id}")
            
            # Route to processor
            incident_id = alert_processor.process(alert)
            
            return Response(
                status=200,
                json={"status": "accepted", "incident_id": incident_id}
            )
        except ValidationError as e:
            logger.error(f"Invalid payload: {e}")
            return Response(status=400, json={"error": str(e)})
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            return Response(status=500, json={"error": "Internal error"})
```

### Component 2: Idempotency Layer

**Location**: `src/state/idempotency_manager.py`

**Responsibilities**:
1. Generate alert group hash: HASH(service_name + alert_type + environment)
2. Check if alert group exists in Firestore
3. If exists: increment counter, skip LLM analysis, return existing incident
4. If new: create group, proceed to analysis

**Pseudocode**:
```python
class IdempotencyManager:
    def get_or_create_alert_group(self, alert: AlertPayload) -> AlertGroup:
        # Hash the alert
        group_id = self.hash_alert(
            service_name=alert.service_name,
            alert_type=self.classify_alert(alert),
            environment=alert.labels.get("environment", "unknown")
        )
        
        # Check if group exists
        existing_group = firestore.get("alert_groups", group_id)
        
        if existing_group:
            # Alert is part of ongoing incident (flapping)
            existing_group.occurrence_count += 1
            existing_group.last_occurrence = alert.timestamp
            
            if existing_group.occurrence_count % 5 == 0:
                # Update Jira with count every 5 occurrences
                jira.add_comment(
                    existing_group.jira_ticket_url,
                    f"Still firing. {existing_group.occurrence_count} occurrences."
                )
            
            firestore.update("alert_groups", group_id, existing_group)
            return existing_group  # SKIP LLM ANALYSIS
        else:
            # NEW incident
            new_group = AlertGroup(
                alert_type=self.classify_alert(alert),
                service_name=alert.service_name,
                environment=alert.labels.get("environment"),
                first_occurrence=alert.timestamp,
                occurrence_count=1,
                created_at=datetime.now(),
                expires_at=datetime.now() + timedelta(minutes=60)
            )
            firestore.create("alert_groups", group_id, new_group)
            return new_group
```

### Component 3: Deterministic Router

**Location**: `src/routing/deterministic_router.py`

**Responsibilities**:
1. Load customer's team routing rules from Firestore
2. Apply regex pattern matching (not LLM)
3. Assign team deterministically
4. Return team assignment with confidence score

**Pseudocode**:
```python
class DeterministicRouter:
    def route_alert(self, alert: AlertPayload, customer_id: str) -> TeamAssignment:
        # Load customer config
        config = firestore.get("customers", customer_id)
        rules = config.team_routing_rules
        
        # Try each rule in order
        for rule in rules:
            if self.matches_pattern(alert, rule["pattern"]):
                return TeamAssignment(
                    team=rule["assigned_team"],
                    confidence=rule["confidence"],
                    rule_matched=rule["id"]
                )
        
        # Fallback (should never reach here if config is valid)
        return TeamAssignment(
            team="platform-infra",
            confidence=0.0,
            rule_matched="fallback"
        )
    
    def matches_pattern(self, alert: AlertPayload, pattern: str) -> bool:
        # Pattern examples:
        # "service:payment-*" → matches alert.service_name == "payment-*"
        # "category:Database.*" → matches alert category starts with "Database"
        # "*" → matches anything
        
        import re
        pattern_regex = pattern.replace("*", ".*")
        return re.match(pattern_regex, f"{alert.service_name}")
```

### Component 4: Context Aggregator & Sanitizer

**Location**: `src/context/aggregator.py` and `src/context/sanitizer.py`

**Responsibilities**:
1. Query GCP APIs for logs, metrics, deployments
2. Scrub secrets using deterministic regex
3. Truncate to token budget (4K max)
4. Return sanitized context

**Pseudocode**:
```python
class ContextAggregator:
    def aggregate(self, alert: AlertPayload, customer_id: str) -> AggregatedContext:
        # Fetch logs
        logs = self.fetch_logs(alert)
        
        # Fetch metrics
        metrics = self.fetch_metrics(alert)
        
        # Fetch recent deployments
        deployments = self.fetch_deployments(alert, limit=5)
        
        # Combine
        raw_context = {
            "logs": logs,
            "metrics": metrics,
            "deployments": deployments
        }
        
        # Sanitize
        sanitizer = ContextSanitizer()
        clean_context = sanitizer.sanitize(raw_context)
        
        return clean_context

class ContextSanitizer:
    SECRET_PATTERNS = [
        r'(bearer\s+|authorization:\s*)[\w\-\.]+',
        r'(api_key|apikey)\s*[=:]\s*[\w\-\.]+',
        r'(password|passwd)\s*[=:]\s*[\w\-\.]+',
        r'(database_url|db_uri)\s*[=:]\s*[^\s]+',
        r'\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b',  # Credit card
        r'\b\d{3}-\d{2}-\d{4}\b'  # SSN
    ]
    
    MAX_LOG_LINES = 100
    MAX_TOKENS = 4000
    
    def sanitize(self, raw_context: dict) -> SanitizedContext:
        # Step 1: Scrub logs
        sanitized_logs = self.scrub_secrets(raw_context["logs"])
        
        # Step 2: Truncate to line limit
        truncated_logs = self.truncate_lines(sanitized_logs, self.MAX_LOG_LINES)
        
        # Step 3: Enforce token budget
        if self.estimate_tokens(truncated_logs) > self.MAX_TOKENS:
            truncated_logs = self.truncate_lines(sanitized_logs, 50)
        
        return SanitizedContext(
            logs=truncated_logs,
            metrics=raw_context["metrics"],
            deployments=raw_context["deployments"],
            context_quality="complete" if not truncated else "truncated"
        )
    
    def scrub_secrets(self, logs: str) -> str:
        sanitized = logs
        for pattern in self.SECRET_PATTERNS:
            sanitized = re.sub(
                pattern,
                r'\1[REDACTED_SECRET]',
                sanitized,
                flags=re.IGNORECASE
            )
        return sanitized
```

### Component 5: LLM Agent Orchestrator

**Location**: `src/agent/orchestrator.py`

**Responsibilities**:
1. Invoke LLM (Claude or Gemini) with sanitized context
2. Parse LLM response
3. Validate output structure
4. Return incident report

**Pseudocode**:
```python
class LLMAgentOrchestrator:
    def __init__(self, model: str = "claude-sonnet-4-6"):
        self.model = model
        self.client = AnthropicClient()  # or VertexAI client
    
    def analyze(self, context: SanitizedContext, alert: AlertPayload) -> IncidentAnalysis:
        # Build prompt
        system_prompt = self.build_system_prompt()
        user_prompt = self.build_user_prompt(context, alert)
        
        # Invoke LLM with tool use
        response = self.client.messages.create(
            model=self.model,
            max_tokens=2000,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
            tools=self.define_tools()
        )
        
        # Process response
        analysis = self.parse_response(response)
        
        # Validate structure
        self.validate_analysis(analysis)
        
        return analysis
    
    def define_tools(self) -> List[Tool]:
        return [
            Tool(
                name="query_gcp_logs",
                description="Query logs",
                input_schema={...}
            ),
            # ... other tools
        ]
    
    def build_system_prompt(self) -> str:
        return """
You are an expert SRE diagnosing production incidents.

CRITICAL RULES:
1. Base all conclusions on evidence from provided logs and metrics.
2. Do NOT infer causes without supporting data.
3. Provide 2-3 actionable recommendations prioritized by impact.
4. Include confidence score (0-1) for your root cause analysis.
5. If you don't have enough context, say so clearly.

Output must be valid JSON matching this structure:
{
    "root_cause": "string",
    "confidence": float (0-1),
    "contributing_factors": ["string"],
    "recommendations": [
        {"priority": int, "action": "string", "rationale": "string", "effort": "low|medium|high"}
    ]
}
        """
```

### Component 6: Incident Creator

**Location**: `src/incidents/incident_creator.py`

**Responsibilities**:
1. Format incident data into Jira ticket
2. Call Jira API to create ticket
3. Handle Jira API failures (fallback to Cloud Tasks)
4. Update alert group with incident reference

**Pseudocode**:
```python
class IncidentCreator:
    def create_incident(self, analysis: IncidentAnalysis, alert_group: AlertGroup, customer_id: str) -> Incident:
        # Format Jira ticket
        ticket_data = self.format_jira_ticket(analysis, alert_group, customer_id)
        
        try:
            # Try primary path: Jira API
            ticket = self.create_jira_ticket(ticket_data, customer_id)
            incident_id = ticket.key
            jira_url = ticket.url
        except JiraAPIError as e:
            # Fallback: Cloud Tasks queue
            logger.error(f"Jira API failed: {e}. Using Cloud Tasks fallback.")
            ticket = self.queue_to_cloud_tasks(ticket_data, customer_id)
            incident_id = f"queued-{uuid4()}"
            jira_url = None
        
        # Create incident record
        incident = Incident(
            incident_id=incident_id,
            jira_ticket_url=jira_url,
            analysis=analysis,
            created_at=datetime.now()
        )
        
        # Store in Firestore
        firestore.create("incidents", incident_id, incident)
        
        # Update alert group
        alert_group.incident_created = True
        alert_group.incident_id = incident_id
        firestore.update("alert_groups", alert_group.id, alert_group)
        
        return incident
    
    def format_jira_ticket(self, analysis: IncidentAnalysis, alert_group: AlertGroup, customer_id: str) -> dict:
        return {
            "fields": {
                "project": {"key": "INFRA"},
                "issuetype": {"name": "Incident"},
                "summary": f"[{alert_group.severity.upper()}] {alert_group.service_name} - {analysis.root_cause}",
                "description": self.render_description(analysis, alert_group),
                "assignee": {"name": alert_group.assigned_team},
                "priority": self.map_severity_to_priority(alert_group.severity),
                "labels": ["incident", "agentic-sre", alert_group.service_name]
            }
        }
```

---

## Reference Implementations

### Reference Impl 1: Full Alert Processing Pipeline

**File**: `src/pipeline/alert_processor.py`

```python
class AlertProcessor:
    def __init__(self, config: Config):
        self.idempotency = IdempotencyManager()
        self.router = DeterministicRouter()
        self.aggregator = ContextAggregator()
        self.sanitizer = ContextSanitizer()
        self.agent = LLMAgentOrchestrator()
        self.incident_creator = IncidentCreator()
        self.logger = CloudLogger()
    
    def process(self, alert: AlertPayload) -> str:
        """
        Full pipeline: Alert → Incident (or queue for async processing)
        
        Returns: incident_id
        """
        trace_id = str(uuid4())
        
        try:
            self.logger.info(f"Starting alert processing", extra={"trace_id": trace_id, "alert_id": alert.alert_id})
            
            # Step 1: Idempotency
            alert_group = self.idempotency.get_or_create_alert_group(alert)
            
            # If recurring alert, skip analysis
            if not alert_group.created_now:
                self.logger.info(f"Alert is recurring (occurrence {alert_group.occurrence_count})", extra={"trace_id": trace_id})
                return alert_group.incident_id
            
            # Step 2: Routing
            team_assignment = self.router.route_alert(alert, alert.customer_id)
            alert_group.assigned_team = team_assignment.team
            
            # Step 3: Context Aggregation & Sanitization
            context = self.aggregator.aggregate(alert, alert.customer_id)
            context = self.sanitizer.sanitize(context)
            
            # Step 4: LLM Analysis
            analysis = self.agent.analyze(context, alert)
            
            # Step 5: Incident Creation
            incident = self.incident_creator.create_incident(analysis, alert_group, alert.customer_id)
            
            self.logger.info(f"Incident created", extra={
                "trace_id": trace_id,
                "incident_id": incident.incident_id,
                "processing_time_ms": elapsed_ms
            })
            
            return incident.incident_id
            
        except Exception as e:
            self.logger.error(f"Alert processing failed: {e}", extra={"trace_id": trace_id})
            # Queue to Pub/Sub for retry
            self.queue_for_retry(alert, trace_id)
            raise
```

---

## Error Handling & Recovery

### Failure Scenarios & Responses

| Scenario | Detection | Recovery |
|----------|-----------|----------|
| **Invalid alert payload** | JSON schema validation fails | Return 400, log error, alert NOT queued |
| **Firestore read fails** | Query exception on alert_group check | Queue to Pub/Sub, return 202 Accepted |
| **GCP Logging API timeout** | >30s for log query | Use last 100 lines cached, continue |
| **GitHub API rate limit** | 429 response | Skip source code, continue with logs only |
| **Jira API fails** | API error response | Queue to Cloud Tasks, still return 200 |
| **LLM timeout** | >5s latency | Use simplified analysis, lower confidence |
| **LLM hallucination** | Confidence < 0.5 | Still create ticket, mark "requires_review" |
| **Cloud Run crashes** | Service unavailable | Pub/Sub buffer holds alerts, manual recovery |

---

## Deployment Architecture

### GCP Infrastructure (IaC)

**File**: `deploy/terraform/main.tf`

```hcl
# Cloud Run Service
resource "google_cloud_run_service" "agentic_sre" {
  name            = "agentic-sre-agent"
  location        = var.gcp_region
  project         = var.gcp_project
  
  template {
    spec {
      containers {
        image = "gcr.io/${var.gcp_project}/agentic-sre:latest"
        env {
          name  = "GCP_PROJECT"
          value = var.gcp_project
        }
      }
      timeout_seconds = 60
    }
  }
}

# Firestore
resource "google_firestore_database" "database" {
  name       = "agentic-sre-db"
  project    = var.gcp_project
  location_id = var.gcp_region
  type       = "DATASTORE_MODE"
  
  # TTL policy for alert_groups
  # (Set via Firestore console for now)
}

# Pub/Sub Topic (Fallback)
resource "google_pubsub_topic" "fallback_alerts" {
  name    = "agentic-sre-fallback-alerts"
  project = var.gcp_project
}

# Cloud Tasks Queue
resource "google_cloud_tasks_queue" "incidents" {
  name     = "agentic-sre-incidents"
  location = var.gcp_region
  project  = var.gcp_project
}
```

### Deployment Pipeline

```
1. Engineer commits to main
2. GitHub Actions:
   - Runs unit tests
   - Builds Docker image
   - Pushes to GCR
   - Deploys to staging Cloud Run
3. Staging validation (1 hour)
4. Deploy to production Cloud Run
5. Monitor metrics (uptime, latency, errors)
```

---

## Next Steps

This TDD is **code-ready**. Engineers can:

1. **Week 1**: Implement components in order (1-6)
2. **Week 2**: Integration testing
3. **Week 3**: Demo preparation
4. **Week 4**: Early customer onboarding

See **Implementation Specification** (separate document) for week-by-week tasks.

