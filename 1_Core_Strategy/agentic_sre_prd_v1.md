# Agentic SRE Platform - MVP Product Requirements Document

**Document Version**: 1.0  
**Date**: June 4, 2026  
**Owner**: Platform Architecture  
**Status**: Draft - Ready for Design Review

---

## Executive Summary

This PRD defines the MVP for **Agentic SRE**, a platform that automates incident detection, triage, and routing using LLM-powered agents. The MVP focuses on reducing MTTR (Mean Time To Response) for L1 operations teams by automating the manual work of categorizing alerts, creating incidents, and assigning them to appropriate teams.

**Core Value Proposition**: Transform incident response from manual triage (hours) to autonomous analysis with human approval (minutes).

---

## Problem Statement

### Current State Pain Points

1. **L1 engineers spend 30-40% of time on repetitive triage**
   - Reading alerts and alert context
   - Searching logs to understand root cause
   - Determining incident category and severity
   - Finding the right team to assign it to
   - Creating tickets with relevant context

2. **Incident Response Time is High**
   - Manual triage adds 15-30 minutes to MTTR
   - Information gathering is error-prone (context gets lost)
   - Team assignments are often incorrect on first try

3. **Knowledge Gap Between L1 and L2/L3**
   - L1 often lacks deep system knowledge
   - Engineers repeat diagnosis work that's already been done
   - No institutional learning from incident patterns

### Target Users

- **Primary**: L1/L2 operations engineers at organizations with 50-1000+ services
- **Secondary**: SRE teams automating their own incident workflows
- **Tertiary**: Platform teams building observability infrastructure

### Success Definition

A 60% reduction in time-to-incident-creation and >80% accuracy on first-time team assignment.

---

## MVP Scope & Requirements

### Phase 1: Triage & Routing Foundation (Weeks 1-3)

**Goal**: Build agent that can categorize incidents and route to correct team with >80% accuracy

#### 1.1 Incident Type: Pod/Service Crashes

**Rationale**: 
- High frequency (30-40% of incidents)
- Deterministic root causes (OOMKill, CrashLoopBackOff, code regression)
- Bounded remediation options (increase memory, rollback, fix code)
- Safe to test end-to-end without live remediation

**Detection Criteria**:
- Pod restart loops detected in GCP Cloud Monitoring
- Container exit codes: 137 (OOMKill), 1 (general crash)
- Pod status: CrashLoopBackOff

#### 1.2 Alert Ingestion

**Mechanism**: Webhook receiver
- Accept POST requests with alert payload
- Normalize to standard schema (regardless of source system)
- Queue for processing based on severity

**Supported Alert Sources (Phase 1)**:
- GCP Cloud Monitoring (native webhooks)
- Generic webhook format (for Prometheus, custom systems)

**Not supported yet**: Datadog, New Relic, PagerDuty (add in Phase 2)

**Alert Payload Schema**:
```json
{
  "alert_id": "string",
  "alert_name": "string",
  "severity": "critical|warning|info",
  "resource_type": "gcp_gke_pod|gcp_cloud_run|vm_instance",
  "resource_id": "string",
  "service_name": "string",
  "timestamp": "RFC3339",
  "metric_name": "string",
  "metric_value": "number",
  "labels": {
    "environment": "prod|staging|dev",
    "region": "string"
  }
}
```

#### 1.3 Agent Analysis Pipeline

The agent must perform:

1. **Alert Context Gathering**
   - Query GCP Cloud Logging for recent container logs (last 30 minutes)
   - Query GCP Cloud Monitoring for metrics (CPU, memory, restart count trends)
   - Determine if this is a new incident or recurring pattern

2. **Root Cause Analysis**
   - Parse error messages and stack traces from logs
   - Correlate with recent deployments (using GCP Cloud Deployment Manager API)
   - Identify pattern: Is this OOMKill? Segfault? Application exception?
   - Check if it correlates with traffic spikes or config changes

3. **Data Sources Available to Agent**
   - GCP Cloud Logging API (logs)
   - GCP Cloud Monitoring API (metrics, time series)
   - GCP Cloud Deployment Manager API (recent deployments)
   - GitHub/GitLab APIs (source code, recent commits)
   - Customer-provided config repository (if available)

4. **Output: Incident Classification & Recommendations**
   ```
   {
     "incident_id": "generated-uuid",
     "classification": {
       "category": "Infrastructure.Compute.ContainerCrash",
       "subcategory": "OOMKilled",
       "severity": "critical|warning|info",
       "assigned_team": "platform-infra",
       "confidence": 0.95
     },
     "analysis": {
       "root_cause": "Container memory limit exceeded. Service consuming 2.1GB against 2GB limit after deployment v1.45.2",
       "contributing_factors": [
         "Memory leak in new version introduced in commit abc123",
         "Traffic spike 2x normal (detected 15min before crash)"
       ],
       "evidence": {
         "log_excerpt": "...",
         "metric_spike_detected": "memory usage increased linearly over 20min",
         "deployment_correlation": "Deploy of v1.45.2 happened 5min before first crash"
       }
     },
     "recommendations": [
       {
         "priority": 1,
         "action": "Increase memory limit to 3GB as immediate mitigation",
         "rationale": "Container was at 99% utilization",
         "risks": "May mask underlying memory leak if not fixed in parallel"
       },
       {
         "priority": 2,
         "action": "Investigate memory leak in v1.45.2, compare with v1.44.1",
         "rationale": "Linear memory growth visible in metrics, suggests leak not temporary spike",
         "effort": "medium"
       },
       {
         "priority": 3,
         "action": "Consider rollback to v1.44.1 if memory increase still occurs after limit adjustment",
         "rationale": "Version prior to memory regression was stable",
         "effort": "low"
       }
     ],
     "links": {
       "logs_url": "https://console.cloud.google.com/...",
       "metrics_dashboard": "https://console.cloud.google.com/...",
       "recent_deployments": "v1.45.2 (5min before crash), v1.45.1 (2h before)"
     }
   }
   ```

#### 1.4 Incident Categorization Taxonomy

**Default Taxonomy** (customers can override):
- `Infrastructure.Compute.ContainerCrash` (pod/container exit)
- `Infrastructure.Compute.OOMKilled` (memory limit exceeded)
- `Infrastructure.Compute.CrashLoopBackOff` (rapid restart loop)
- `Application.CrashDump` (application exception/segfault)

**Team Assignment Logic**:
- If `OOMKilled` → assign to "platform-infra" 
- If `CrashLoopBackOff` + application error in logs → assign to application owner
- Default fallback: "on-call-team"

**Configuration**: YAML file per customer defining:
```yaml
categories:
  - id: Infrastructure.Compute.ContainerCrash
    keywords: [CrashLoopBackOff, pod, container, exit]
    assigned_team: platform-infra
    severity_override: critical

team_mappings:
  - pattern: "service:payment-*"
    team: payment-platform
  - pattern: "service:*"
    team: platform-infra
```

#### 1.5 Incident Creation

**Target Systems**:
- **Primary**: Jira Cloud (auto-create tickets in customer's workspace)
- **Secondary**: ServiceNow (if customer has it)
- **Fallback**: GCP Cloud Tasks (queue for customer to process)

**Jira Ticket Template**:
```
Title: [CRITICAL] Pod Crash: {service_name} - {root_cause_brief}

Description:
## Incident Summary
- **Category**: Infrastructure.Compute.ContainerCrash
- **Service**: payment-service
- **Environment**: production
- **Detected**: 2026-06-04 14:23:45 UTC

## Root Cause
{root_cause_analysis}

## Recommendations
1. {recommendation_1}
2. {recommendation_2}
3. {recommendation_3}

## Supporting Evidence
- **Recent Deployment**: v1.45.2 (deployed 5min before crash)
- **Memory Trend**: Linear increase from 1.2GB to 2.1GB over 20 minutes
- **Log Excerpt**: {relevant_logs}

## Next Steps
- [ ] Implement recommended fix
- [ ] Validate in staging
- [ ] Deploy fix to production
- [ ] Monitor for 30 minutes post-deployment

Labels: incident, sre, automated, {service_name}, {severity}
Assigned to: {team_lead}
Priority: {severity_mapped_to_priority}
```

#### 1.6 Processing Model (Severity-Based)

| Severity | Processing | SLA |
|----------|-----------|-----|
| Critical | Synchronous (real-time) | <30s to ticket creation |
| Warning | Async, prioritized | <2min to ticket creation |
| Info | Batch every 5 minutes | <5min to ticket creation |

**Severity Determination**:
1. Use explicit severity from alert if present
2. Infer from context:
   - Is production environment? → critical
   - Is customer-facing service affected? → critical
   - Multiple restarts in last 5 min? → warning
   - Single restart? → info

#### 1.7 Deployment Model (Phase 1)

**Architecture**: Single-tenant SaaS
- One instance per customer (managed by us)
- Deployed to GCP Cloud Run (scalable, low ops overhead)
- Each customer gets isolated Cloud Run service + Cloud Tasks queue

#### 1.4 Customer Integration Required (Security-First Approach)

**1. Alert Webhook Configuration**
- Configure webhook URL in their alerting system
- Provide Pub/Sub fallback topic for resilience

**2. GitHub/GitLab Authentication (GitHub Apps, Not Personal Tokens)**

**Why GitHub Apps Instead of PAT**:
- ❌ Personal Access Tokens: Blanket repo:read access to entire organization (supply chain risk)
- ✅ GitHub Apps: Scoped to specific repos, read-only, auditable, can be revoked instantly

**Setup Process**:
```
1. Customer creates GitHub App in their organization settings
2. Scopes required:
   - contents: read  (only read files, no write)
   - metadata: read  (read public repo metadata)
3. Install app on ONLY the repositories we need (not entire org)
4. Customer provides app credentials to Agentic SRE platform
5. We use app credentials to fetch files
```

**Firestore Storage** (encrypted at rest):
```python
{
  "customer_id": "acme-corp",
  "github_app": {
    "app_id": "123456",
    "private_key": "[ENCRYPTED]",
    "installation_id": "789012"
  },
  "allowed_repos": [
    "acme-corp/payment-service",
    "acme-corp/auth-service"
  ]
}
```

**3. Jira API Credentials**
- Provide Jira API token with create-only permissions
- Restrict to incident creation, no deletion/modification

**4. Upload Customer Taxonomy Config** (YAML)
```yaml
incident_categories:
  - id: Infrastructure.Compute.ContainerCrash
    keywords: [CrashLoopBackOff, OOMKilled]
    assigned_team: platform-infra

team_mappings:
  - pattern: "service:payment-*"
    team: payment-platform
```

**Infrastructure**:
```
GCP Cloud Run (Agent Service)
├── Alert Webhook Receiver
├── Analysis Engine (LLM + Tools)
├── Incident Creator (Jira/ServiceNow/Cloud Tasks)
└── Audit Logging

GCP Firestore (Customer Config + Audit Trail)
GCP Cloud Tasks (Incident Queue for Fallback)
GCP Pub/Sub (Emergency Buffer for Platform Downtime)
GCP Cloud Logging (All agent actions, metrics, errors)
```

#### 1.8 Emergency Bypass / Break Glass Procedure

**Problem**: If Cloud Run goes down or webhook receiver drops payloads, we lose visibility into production alerts.

**Solution**: Pub/Sub Fallback Buffer with Manual Recovery Path

```
┌─────────────────────────────┐
│ Customer Alert System       │
│ (Prometheus/Datadog/etc)    │
└──────────────┬──────────────┘
               │
        ┌──────┴──────┐
        ▼             ▼
   [ Webhook ]   [ Pub/Sub Topic ]
   (Primary)     (Fallback Buffer)
        │             │
        ▼             ▼
   Cloud Run      Buffer Messages
   (Normal Path)  (If Cloud Run Down)
        │             │
        └─────┬───────┘
              ▼
         Process Alert
```

**Implementation**:

1. **Primary Path** (normal operation):
   - Customer sends webhook to Cloud Run directly
   - Cloud Run receives, processes, creates Jira ticket
   - Success

2. **Fallback Path** (if Cloud Run unavailable):
   - Customer has Pub/Sub topic configured as secondary webhook target
   - Messages queue in Pub/Sub (24-hour retention)
   - When Cloud Run recovers, pull from Pub/Sub queue and process

3. **Manual Recovery Path** (if both paths fail):
   - L1 team manually exports unprocessed alerts from Pub/Sub
   - Manually creates Jira tickets with alert details
   - Pub/Sub messages are logged in Cloud Logging for audit

**Configuration Required from Customer**:
```yaml
# In customer's alerting config
webhooks:
  - url: https://agentic-sre.platform.com/alerts/ingest  # Primary
    type: json
  - pubsub_topic: projects/customer-project/topics/agentic-sre-fallback  # Fallback
    type: pubsub
```

**SLA**:
- Primary webhook: <30s to ticket creation
- Pub/Sub fallback: <5min to ticket creation
- Manual recovery: Documented runbook, 15min to execution

**Testing**:
- Monthly "break glass drill": Simulate Cloud Run downtime, verify Pub/Sub picks up alerts
- Verify manual recovery procedure works end-to-end

---

### Phase 2: Demo & Validation (Weeks 3-4)

**Goal**: Build working end-to-end demo deployable to staging

#### 2.1 Demo Scenario

**Incident to Simulate**: Pod OOMKill in GCP GKE cluster

**Steps**:
1. Alert webhook fires (simulated or real)
2. Agent receives alert, queries GCP APIs
3. Agent analyzes logs, metrics, recent deployments
4. Agent generates RCA and recommendations
5. Agent creates Jira ticket with full analysis
6. Demonstrate ticket was created with correct team assignment

**Demo Environment**:
- GCP GKE cluster with intentionally crashing pod
- Synthetic or real logs in Cloud Logging
- Jira project configured for demo
- Agent running on Cloud Run

---

### Phase 3: Early Customer Deployment (Weeks 5+)

**Goal**: Deploy to one early customer, gather real feedback

**Success Criteria**:
- Agent successfully triages >80% of incoming pod crash alerts
- Team assignments are correct on first try >80% of the time
- Agent RCAs provide value (engineers don't have to re-analyze from scratch)
- MTTR reduced by >50% compared to baseline

**Metrics to Track**:
- Accuracy of category assignment
- Accuracy of team assignment
- Acceptance rate of recommendations
- Time saved per incident (estimated by customer feedback)
- Agent error rate (failures to analyze, API errors, etc.)

---

## Out of Scope (Phase 1)

These are **intentionally deferred** to maintain MVP focus:

- ❌ **Multiple incident types**: Only pod crashes in Phase 1
- ❌ **Live remediation**: Agent only recommends, humans approve
- ❌ **Self-healing**: No automatic fixes (adds complexity and risk)
- ❌ **Multi-tenant SaaS**: Single-tenant only (add later)
- ❌ **Self-hosted option**: SaaS only for MVP (self-hosted adds deployment complexity)
- ❌ **Datadog/New Relic/PagerDuty integration**: GCP native + generic webhooks only
- ❌ **Dependency graph analysis**: Too complex for MVP
- ❌ **SLO impact calculation**: Add in Phase 2
- ❌ **Runbook linking**: Add in Phase 2
- ❌ **Historical incident learning**: Add in Phase 2

---

## Technical Architecture (MVP) - Deterministic Agentic SRE Framework

The architecture follows the **Deterministic Agentic SRE (DAS)** pattern, which shields the LLM from handling business logic, security concerns, or data consistency. Instead, deterministic layers handle these responsibilities, while the LLM focuses exclusively on synthesis and reasoning over clean, safe data.

### Component Overview

```
┌────────────────────────────────────────────────────────────────┐
│                    Customer Environment                         │
│  (GCP + Jira + Alert System + GitHub)                          │
└────────────────────────────────────────────────────────────────┘
                              ↓ webhook
┌────────────────────────────────────────────────────────────────┐
│                  Agentic SRE Platform (GCP)                    │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Cloud Run: Alert Ingestion & Processing               │ │
│  │                                                         │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ 1. Alert Webhook Receiver & Normalizer            │ │ │
│  │ │    - Normalize payload to standard schema          │ │ │
│  │ │    - Extract: service, alert_type, severity       │ │ │
│  │ │    - Validate payload structure                   │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  │         ↓                                               │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ 2. Idempotency & Flapping Mitigation Layer       │ │ │
│  │ │    [DETERMINISTIC - No LLM involved]              │ │ │
│  │ │    - Check Firestore for existing alert group     │ │ │
│  │ │    - Hash: (service_name + alert_type + env)      │ │ │
│  │ │    - If exists: increment counter, skip analysis  │ │ │
│  │ │    - If new: create group, proceed to routing     │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  │         ↓                                               │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ 3. Deterministic Operational Router                │ │ │
│  │ │    [DETERMINISTIC - No LLM involved]              │ │ │
│  │ │    - Apply static regex/config rules               │ │ │
│  │ │    - Assign team via pattern matching              │ │ │
│  │ │    - Set severity (not inferred by LLM)            │ │ │
│  │ │    - Fast, consistent, predictable                │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  │         ↓                                               │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ 4. Context Aggregator & Sanitizer                 │ │ │
│  │ │    [DETERMINISTIC - No LLM involved]              │ │ │
│  │ │    - Fetch logs, metrics, deployments             │ │ │
│  │ │    - Scrub secrets/PII using regex patterns        │ │ │
│  │ │    - Truncate logs to token budget (max 4K tokens) │ │ │
│  │ │    - Ensure data is safe for external LLM         │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  │         ↓                                               │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ 5. LLM Tool Orchestration Engine (Claude)          │ │ │
│  │ │    [AGENTIC - RCA + Recommendations ONLY]         │ │ │
│  │ │    - Receive clean, truncated context             │ │ │
│  │ │    - Query structured GCP/GitHub APIs             │ │ │
│  │ │    - Generate root cause analysis                 │ │ │
│  │ │    - Produce 2-3 actionable recommendations       │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  │         ↓                                               │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ 6. Incident Creator & Outbound Gateway             │ │ │
│  │ │    - Create Jira/ServiceNow ticket                 │ │ │
│  │ │    - Queue to Cloud Tasks if no ticket system      │ │ │
│  │ │    - Update alert group state in Firestore         │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  │         ↓                                               │ │
│  │ ┌────────────────────────────────────────────────────┐ │ │
│  │ │ 7. Telemetry & Drift Monitoring                    │ │ │
│  │ │    - Track agent accuracy & performance            │ │ │
│  │ │    - Monitor for hallucinations/drift              │ │ │
│  │ │    - Alert if success rate drops below SLO         │ │ │
│  │ └────────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Firestore: Stateful Data Layer                          │ │
│  │  - Alert Groups (de-duplication state)                  │ │
│  │  - Customer configs (taxonomy, team mappings)           │ │
│  │  - API credentials (encrypted)                          │ │
│  │  - TTL policies (auto-cleanup of resolved alerts)       │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Cloud Tasks: Async Queue (Fallback)                      │ │
│  │  - For customers without Jira/ServiceNow                │ │
│  │  - For rate-limited or failed API calls                 │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Cloud Logging: Comprehensive Audit Trail                 │ │
│  │  - All agent decisions, reasoning, and outputs           │ │
│  │  - API calls, errors, and performance metrics            │ │
│  │  - Drift monitoring alerts                               │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

### Why This Architecture Matters

| Layer | Why It Exists | What It Prevents |
|-------|---------------|------------------|
| **Idempotency & Flapping Mitigation** | Alerts fire in bursts (pod restarts 50x in 10s) | 50 Jira tickets, 50 LLM calls, token cost explosion, ticket spam |
| **Deterministic Router** | Team assignment via regex is fast and consistent | LLM hallucinating wrong team, paying for LLM inference on 100% of alerts |
| **Context Sanitizer** | Logs contain secrets, PII, and are massive | Credential leakage to external LLM, token limit errors, compliance violations |
| **LLM Isolation** | Agent focuses on reasoning, not business logic | Context bloat, non-deterministic behavior, expensive token waste |
| **Telemetry Layer** | Monitor agent accuracy and drift over time | Silent degradation, users losing trust without knowing why |

### Data Flow: Alert to Incident

```
1. Alert fires in customer's system
   └─> POST to /alerts/ingest webhook

2. Webhook receiver
   ├─ Parse & normalize payload
   ├─ Extract: alert_id, severity, resource, service
   ├─ Determine processing mode (sync/batch)
   └─> If critical: sync; otherwise: queue to Cloud Tasks

3. Agent receives alert (sync or dequeued from Cloud Tasks)
   ├─ Fetch customer config from Firestore
   ├─ Extract customer GCP project ID, Jira workspace, GitHub org
   └─> Start analysis

4. Diagnostic reasoning
   ├─ Query: "What is the status of this pod in the last 30 minutes?"
   │  └─> Call GCP Cloud Logging API
   ├─ Query: "What are the memory/CPU metrics?"
   │  └─> Call GCP Cloud Monitoring API
   ├─ Query: "What deployments happened recently?"
   │  └─> Call GCP Cloud Deployment Manager API
   ├─ Query: "What does the source code of this service look like?"
   │  └─> Call GitHub API
   └─> LLM reasons over collected data, generates RCA

5. Classification
   ├─ Determine incident category (using customer taxonomy)
   ├─ Determine assigned team (using customer team mappings)
   ├─ Determine severity level
   └─> Output: structured incident report

6. Incident creation
   ├─ If Jira configured:
   │  └─> Call Jira API, create ticket
   ├─ Else if ServiceNow configured:
   │  └─> Call ServiceNow API, create ticket
   └─ Else:
      └─> Push to Cloud Tasks queue

7. Audit logging
   ├─ Log all decisions & reasoning
   ├─ Log API calls & responses
   ├─ Store accuracy feedback (manual corrections by humans)
   └─> Enable continuous improvement

8. Return to webhook caller
   └─> 200 OK with incident_id
```

### Alert De-Duplication & Flapping Mitigation (CRITICAL)

**Problem**: A pod crash can fire 50 alerts in 10 seconds. Without de-duplication, we'd create 50 Jira tickets and call the LLM 50 times.

**Solution**: Firestore-based Alert Grouping with Time-Windowed State

```
Firestore Collection: "alert_groups"

Document ID: HASH(service_name + alert_type + environment)
Example: "payment-service|ContainerCrash|prod"

Document Fields:
{
  "alert_type": "ContainerCrash",
  "service_name": "payment-service",
  "environment": "prod",
  
  "first_occurrence": "2026-06-04T14:23:45Z",
  "last_occurrence": "2026-06-04T14:24:30Z",
  "occurrence_count": 47,
  
  "incident_created": true,
  "incident_id": "inc-20260604-001",
  "jira_ticket_url": "https://jira.company.com/INFRA-1234",
  
  "state": "open",  // or "resolved"
  "last_analysis_timestamp": "2026-06-04T14:23:50Z",
  
  "created_at": "2026-06-04T14:23:45Z",
  "expires_at": "2026-06-04T15:23:45Z"  // TTL: auto-delete after 60 min silence
}
```

**Pseudocode**:

```python
def process_alert(alert):
    group_id = hash(alert.service_name, alert.alert_type, alert.environment)
    
    # Check if we've seen this alert before
    existing_group = firestore.get("alert_groups", group_id)
    
    if existing_group:
        # Alert is part of ongoing incident (flapping)
        firestore.update("alert_groups", group_id, {
            "occurrence_count": existing_group.occurrence_count + 1,
            "last_occurrence": alert.timestamp
        })
        
        # Skip LLM analysis (only update Jira with count every 5 occurrences)
        if existing_group.occurrence_count % 5 == 0:
            jira.add_comment(
                existing_group.jira_ticket_url,
                f"Alert still firing. {existing_group.occurrence_count} occurrences."
            )
        return  # SKIP EXPENSIVE LLM CALL
    
    else:
        # NEW INCIDENT - create group and run analysis
        firestore.create("alert_groups", group_id, {
            "alert_type": alert.alert_type,
            "service_name": alert.service_name,
            "environment": alert.environment,
            "first_occurrence": alert.timestamp,
            "last_occurrence": alert.timestamp,
            "occurrence_count": 1,
            "created_at": alert.timestamp,
            "expires_at": alert.timestamp + 60_minutes
        })
        
        # ONLY NOW: Call expensive LLM analysis
        analysis = llm_agent.analyze(alert)
        
        # Create Jira ticket
        ticket = jira.create_ticket({
            "title": f"[CRITICAL] {alert.service_name} - {analysis.root_cause}",
            "description": analysis.formatted_output(),
            "assigned_team": analysis.assigned_team
        })
        
        # Update group with incident reference
        firestore.update("alert_groups", group_id, {
            "incident_id": ticket.incident_id,
            "jira_ticket_url": ticket.url,
            "incident_created": true
        })
```

**Example Timeline**:

```
T+0s:   Alert 1 fires (payment-service OOMKill)
        → No group exists → Create group → Run LLM → Create Jira ticket INC-001

T+1s:   Alert 2 fires (same pod, same crash)
        → Group exists (occurrence_count=1) → Update count to 2 → SKIP LLM → Return

T+2s:   Alert 3, 4, 5... cascade
        → Group exists → Increment count → No new Jira tickets

T+10s:  47 alerts have fired
        → Group updated: occurrence_count=47, last_occurrence=T+10s
        → Single Jira ticket shows "47 occurrences detected"
        → Single LLM analysis runs (not 47)
        → Estimated token savings: 99% reduction
```

**Cost Impact**: Reduces per-incident cost from O(alert_count) to O(1).

---

### Log Sanitization & Token Budgeting (CRITICAL)

**Problem**: Production logs can be 5MB+ per minute. Sending raw logs to Claude:
- Burns 10x more tokens than necessary
- Hits context window limits
- Fails with API timeouts
- Contains secrets/PII (compliance violation)

**Solution**: Deterministic Sanitizer & Truncator

```python
class ContextSanitizer:
    # Secrets that commonly leak into logs
    SECRET_PATTERNS = [
        r'(bearer\s+|authorization:\s*)[\w\-\.]+',  # Tokens
        r'(api_key|apikey)\s*[=:]\s*[\w\-\.]+',      # API Keys
        r'(password|passwd)\s*[=:]\s*[\w\-\.]+',     # Passwords
        r'(database_url|db_uri)\s*[=:]\s*[^\s]+',    # DB Connections
        r'\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b',  # Credit card numbers
        r'\b\d{3}-\d{2}-\d{4}\b'                      # SSN
    ]
    
    MAX_LOG_LINES = 100  # Limit context to 100 lines
    MAX_TOKENS = 4000    # Never exceed 4K tokens for logs
    
    @staticmethod
    def sanitize(raw_logs: str) -> str:
        # Step 1: Scrub all secrets
        sanitized = raw_logs
        for pattern in ContextSanitizer.SECRET_PATTERNS:
            sanitized = re.sub(
                pattern,
                r'\1[REDACTED_SECRET]',
                sanitized,
                flags=re.IGNORECASE
            )
        
        # Step 2: Truncate to relevant lines (keep last N)
        lines = sanitized.splitlines()
        if len(lines) > ContextSanitizer.MAX_LOG_LINES:
            lines = lines[-ContextSanitizer.MAX_LOG_LINES:]
            lines.insert(0, f"[TRUNCATED] Showing last {ContextSanitizer.MAX_LOG_LINES} of {len(lines)} lines.")
        
        # Step 3: Estimate tokens and enforce hard limit
        estimated_tokens = len(" ".join(lines).split()) * 1.3  # rough estimate
        if estimated_tokens > ContextSanitizer.MAX_TOKENS:
            # If still too large, truncate aggressively
            lines = lines[-(ContextSanitizer.MAX_LOG_LINES // 2):]
            lines.insert(0, "[AGGRESSIVE_TRUNCATION] Only most recent logs included.")
        
        return "\n".join(lines)
```

**Example**:

```
BEFORE (5000 lines, 50KB):
2026-06-04T21:00:00Z ERROR connect to postgres://admin:mysecretpassword123@db.prod.internal:5432/payments
2026-06-04T21:00:01Z ERROR api_key=sk-1234567890abcdef...
2026-06-04T21:00:02Z ERROR Out of memory: cannot allocate 2GB
... (4995 more lines)

AFTER (100 lines, 5KB):
[TRUNCATED] Showing last 100 of 5000 lines.
2026-06-04T21:00:00Z ERROR connect to postgres://admin:[REDACTED_SECRET]@db.prod.internal:5432/payments
2026-06-04T21:00:01Z ERROR api_key=[REDACTED_SECRET]
2026-06-04T21:00:02Z ERROR Out of memory: cannot allocate 2GB
...
```

**Impact**: 
- 90% reduction in tokens sent to LLM
- 100% security (no secrets leak to external API)
- Faster LLM response time
- Token cost reduction: $50/month → $5/month (per customer)

---

### Sanitizer Feedback Loop (Visibility into Truncation)

**Problem**: If we aggressively truncate logs and strip context, how do engineers know the analysis was based on incomplete data?

**Solution**: Explicit Context Quality Signaling

The agent's output ALWAYS includes a `context_quality` field:

```json
{
  "incident_id": "inc-20260604-001",
  "analysis": {
    "root_cause": "Memory leak in v1.45.2",
    "confidence": 0.92
  },
  "context_quality": "complete",  // ← Signal truncation status
  "context_notes": {
    "logs_truncated": false,
    "source_code_fetched": true,
    "sanitization_warnings": []
  }
}
```

**Three Levels of Context Quality**:

| Level | Meaning | Action |
|-------|---------|--------|
| `complete` | Received full logs, no truncation | Normal flow |
| `truncated` | Logs were truncated to 100 lines | Note in Jira: "Based on last 100 log lines" |
| `degraded` | Logs truncated AND secrets scrubbed, possible context loss | Flag in Jira for manual review |

**In Jira Ticket**:
```
## Context Quality Report
- ✅ Logs Truncated: No (received full log set)
- ✅ Source Code Fetched: Yes (pool_allocator.rs:234)
- ⚠️ Sanitization: Scrubbed 2 API_KEY patterns, 1 password

If you believe this analysis is incomplete, view full logs in:
[GCP Cloud Logging Dashboard](https://console.cloud.google.com/logs/...)
```

**Manual Review Trigger**: If `context_quality: "degraded"`, add comment in Jira:
```
⚠️ ALERT: This incident analysis was based on heavily truncated or sanitized logs.
The root cause may be incomplete. Manual log review recommended before remediation.
View full logs here: [link]
```

**Engineer Feedback Loop**: If engineer reviews and finds the analysis was indeed incomplete:
1. Click "Mark Context Issue" in Jira
2. Provide the missing context (e.g., "The real error was X, which was in line 500 of logs")
3. Feedback is logged and improves future truncation heuristics

### Telemetry & Drift Monitoring

**Problem**: How do we know if the agent is degrading? When it starts hallucinating? When model updates break our prompts?

**Solution**: Continuous Telemetry with Automated Alerts

**Metrics to Track** (Cloud Logging):

```
Metric: incident_analysis_accuracy
Type: Gauge (0-100%)
Labels: customer_id, incident_type, assigned_team
Description: % of incidents where assigned team matches actual owning team
SLO: >= 85%
Alert: If drops below 80% for customer

Metric: incident_category_precision
Type: Gauge (0-100%)
Description: % of incidents correctly categorized
SLO: >= 80%
Alert: If drops below 75%

Metric: llm_token_usage
Type: Gauge (tokens)
Labels: customer_id, incident_type
Description: Average tokens consumed per analysis
Baseline: Establish after first week
Alert: If increases >30% from baseline (sign of context bloat/drift)

Metric: llm_response_latency
Type: Histogram (milliseconds)
P50, P95, P99
SLO: P95 < 5000ms for critical alerts
Alert: If P95 exceeds 6000ms

Metric: hallucination_detected
Type: Counter
Description: Manual corrections where agent output was factually wrong
Alert: If count increases 3+ in a day

Metric: false_positive_rate
Type: Gauge (%)
Description: % of created tickets that were later marked "not an incident"
SLO: < 5%
```

**Drift Detection Logic**:

```python
class DriftMonitor:
    # Establish baseline metrics in first week
    BASELINE_ACCURACY = 0.88
    BASELINE_TOKENS = 2500
    
    @staticmethod
    def check_drift(current_metrics):
        # Detect accuracy degradation
        if current_metrics.accuracy < 0.85:
            alert(f"Accuracy drop detected: {current_metrics.accuracy:.1%}")
            # Possible causes: model behavior change, prompt drift, GCP API changes
        
        # Detect token creep (sign of context bloat)
        if current_metrics.avg_tokens > DriftMonitor.BASELINE_TOKENS * 1.3:
            alert(f"Token usage increased: {current_metrics.avg_tokens} vs baseline {DriftMonitor.BASELINE_TOKENS}")
            # Investigate: Are we fetching too much context? Are logs no longer being truncated?
        
        # Detect latency degradation
        if current_metrics.p95_latency > 6000:
            alert(f"P95 latency SLO breach: {current_metrics.p95_latency}ms")
        
        # Detect hallucination spike
        if current_metrics.hallucinations_today > 3:
            alert(f"Hallucination spike detected: {current_metrics.hallucinations_today} today")
            # May indicate model update broke our prompts
```

---

### Tool Definitions (Agent)

The agent will have access to these tools:

```python
tools = [
    {
        "name": "query_gcp_logs",
        "description": "Query GCP Cloud Logging for container/pod logs",
        "input_schema": {
            "resource_type": "gcp_gke_pod | gcp_cloud_run | vm_instance",
            "resource_id": "string",
            "time_window_minutes": "integer (max 60)",
            "filter_expr": "string (optional, GCP Logging filter)"
        }
    },
    {
        "name": "query_gcp_metrics",
        "description": "Query GCP Cloud Monitoring for time series metrics",
        "input_schema": {
            "metric_type": "memory_usage | cpu_usage | restart_count",
            "resource_id": "string",
            "time_window_minutes": "integer (max 60)"
        }
    },
    {
        "name": "get_recent_deployments",
        "description": "Get recent deployments for a service (max 5 most recent)",
        "input_schema": {
            "service_name": "string",
            "limit": "integer (default 5, max 10)"
        }
    },
    {
        "name": "fetch_source_code",
        "description": "Fetch source code ONLY for files explicitly mentioned in stack traces. Never guess file paths.",
        "input_schema": {
            "repo": "string (validated against allowed_repos)",
            "file_paths": "array of strings (must be extracted from stack trace, not guessed)",
            "context_lines": "integer (default 10, max 20)"
        },
        "constraints": {
            "allowed_dirs": ["src/", "lib/", "cmd/", "app/"],
            "blocked_dirs": ["node_modules/", ".git/", "vendor/", "target/", "dist/"],
            "max_files": 3,
            "max_lines_per_file": 200,
            "max_total_tokens": 1500
        },
        "fallback": "If no explicit file paths in stack trace, skip source code and note in output"
    },
    {
        "name": "fetch_config",
        "description": "Fetch application config (k8s manifests, env vars, etc.)",
        "input_schema": {
            "service_name": "string",
            "environment": "prod | staging | dev"
        }
    },
    {
        "name": "generate_incident_report",
        "description": "Output structured incident report for creation",
        "input_schema": {
            "category": "string",
            "assigned_team": "string",
            "root_cause": "string",
            "recommendations": "array of recommendation objects",
            "evidence": "object with supporting data",
            "context_quality": "string (complete | truncated | degraded)"
        }
    }
]
```

**Critical Notes on `fetch_source_code`**:

1. **No Free-Form File Paths**: Agent must extract file paths ONLY from stack traces using regex:
   ```
   Pattern: pool_allocator.rs:234 → Extract "pool_allocator.rs"
   Pattern: /app/src/main.go:145 → Extract "main.go"
   ```

2. **Validation Before Fetch**:
   ```python
   # Pseudocode for the agent's tool use
   extracted_files = regex_extract_from_stack_trace(logs)
   
   if not extracted_files:
       output "[SOURCE_CODE_SKIPPED] No stack trace detected. Using logs + deployments instead."
       skip_tool_call()
   
   validated_files = validate_against_allowed_dirs(extracted_files)
   
   if not validated_files:
       output "[SOURCE_CODE_SKIPPED] Extracted files not in allowed directories."
       skip_tool_call()
   
   # Only now: fetch source code
   fetch_source_code(validated_files)
   ```

3. **Fallback Behavior**: If no explicit file paths in logs, agent should note this in the final report:
   ```
   "context_quality": "degraded"
   "note": "No stack trace with file paths detected. Analysis based on logs and deployment history."
   ```

---

## Success Metrics & KPIs

### Phase 1 Success Criteria

| Metric | Target | How We Measure |
|--------|--------|----------------|
| **Category Accuracy** | >80% | Manual review of 50 generated incidents |
| **Team Assignment Accuracy** | >80% | Compare assigned team vs. actual owning team (from customer) |
| **Agent Availability** | >99% | Uptime of Cloud Run service |
| **Response Latency (Critical)** | <30s | Time from webhook receipt to ticket creation |
| **Response Latency (Standard)** | <5min | Time from alert to ticket for non-critical |
| **False Positive Rate** | <5% | % of alerts that don't actually warrant tickets |

### Phase 2 Success Criteria

| Metric | Target |
|--------|--------|
| **End-to-End Demo** | Successful demo from alert to Jira ticket in <2 minutes |
| **Agent Reasoning Quality** | Engineers find RCAs helpful (qualitative feedback) |
| **Code Quality** | >80% test coverage, documentation complete |

### Phase 3 Success Criteria (Early Customer)

| Metric | Target |
|--------|--------|
| **Category Accuracy** | >80% on customer's real incidents |
| **MTTR Reduction** | >50% compared to customer's baseline |
| **Engineer Feedback** | Positive feedback on agent analysis quality |
| **Incident Volume** | Successfully process >95% of incoming alerts |

---

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|-----------|
| **Alert flapping creates ticket storm** | Jira flooded, LLM cost explosion | High | Firestore-based de-duplication with time-windowed grouping (see "Alert De-Duplication" section). Single incident created per unique alert type, not per alert occurrence. |
| **Raw logs leak secrets to external LLM** | Credential compromise, compliance violation | High | Mandatory context sanitizer (regex scrubbing of API keys, tokens, passwords, PII). Never send raw logs. Test sanitizer against production log samples. |
| **Log context exceeds token budget** | API timeouts, context window errors | Medium | Hard cap at 4K tokens max. Truncate to last 100 lines. Estimate tokens before sending. Monitor token usage in telemetry. |
| **LLM routing causes wrong team assignment** | Customer frustration, slow incident resolution | Medium | Use deterministic regex-based routing instead of LLM. Static config rules. Verify routing accuracy in unit tests. |
| **Agent accuracy degrades over time** | Silent drift, loss of customer trust | Medium | Implement telemetry dashboard (accuracy, precision, tokens, latency). Set SLOs: accuracy >= 85%, category precision >= 80%. Alert on breach. Monthly review of hallucinations. |
| **Source code fetching hallucination** | Context bloat, token waste, wrong code paths | High | Strict constraints: Only fetch files explicitly in stack traces. Validate against whitelist/blacklist. Max 3 files, 200 lines each. Fallback to no source code if no stack trace. |
| **GitHub Personal Token is supply chain risk** | Entire codebase exposed if token leaked | High | Use GitHub Apps with minimal scopes instead. Scoped to specific repos, read-only, auditable, revocable. Document setup in onboarding. |
| **API rate limits (GCP/GitHub/Jira)** | Agent failures mid-analysis | Medium | Implement exponential backoff (max 3 retries, 30s timeout). Cache recent deployments (5min TTL). Fallback to Cloud Tasks if Jira API down. |
| **Customer credential leakage** | Security incident | Low | Encrypt credentials at rest in Firestore. Use minimal IAM permissions (read-only for logs/metrics, create-only for Jira). Audit all credential access. |
| **Agent hallucinates false causes** | Wasted engineer time, lost credibility | Medium | Require all recommendations backed by evidence from logs. Show log excerpts in Jira ticket. Surface confidence score. Manual correction feedback loop trains improvement. |
| **Cloud Run goes down (platform unavailable)** | Loss of alert visibility, manual triage required | Low | Pub/Sub fallback buffer queues alerts during downtime. Manual recovery procedure documented. Monthly "break glass drill" validates recovery path. |
| **Integration complexity delays MVP** | Timeline slip | Low | Start with Jira only, add ServiceNow + Cloud Tasks fallback in Phase 2. Use Jira Python SDK for reliability. |
| **Early customer demands live remediation** | Scope creep, safety risk | High | Clear communication in contract: MVP is read-only (analysis + recommendations). Live remediation requires human approval button, not automation. Document in roadmap as Phase 3. |
| **Cost becomes unsustainable** | Unprofitable service | Medium | De-duplication reduces LLM calls by 95%. Deterministic routing removes 1 LLM call per alert. Caching saves 40% of API calls. Monitor unit economics: target <$0.50 cost per incident. Benchmark Claude vs Gemini 2.5 Pro in Week 1. |
| **Sanitizer strips out actual root cause** | Analysis based on incomplete data | Medium | Context quality signaling: always report if logs were truncated. Flag `context_quality: "degraded"` in Jira. Engineer feedback loop improves heuristics. |
| **LLM model updates break our prompts** | Silent accuracy degradation, hallucinations spike | Medium | Version control all prompts and system messages. Weekly accuracy telemetry checks. Compare metrics across model versions. Revert to previous model if accuracy drops >5%. |

---

## Implementation Roadmap

### Week 1: Foundation & Prototyping
- [ ] Set up GCP infrastructure (Cloud Run, Firestore, Cloud Tasks)
- [ ] Build alert webhook receiver & normalizer
- [ ] Implement customer config management
- [ ] Prototype agent with Claude API (basic log querying)

### Week 2: Agent Capabilities
- [ ] Build all tool integrations (GCP APIs, GitHub, Jira)
- [ ] Implement RCA generation (structured reasoning)
- [ ] Build categorization logic (with fallback to generic taxonomy)
- [ ] Implement incident creator (Jira API)

### Week 3: Testing & Demo Prep
- [ ] End-to-end testing with synthetic incidents
- [ ] Build demo scenario (intentional pod crash)
- [ ] Implement audit logging & debugging
- [ ] Prepare demo walkthrough

### Week 4: Demo & Refinement
- [ ] Live demo to stakeholders
- [ ] Incorporate feedback
- [ ] Prepare early customer deployment

### Week 5+: Early Customer Deployment
- [ ] Onboard first customer
- [ ] Monitor & support
- [ ] Collect metrics & feedback
- [ ] Plan Phase 2 improvements

---

## Platform Abstraction Roadmap (Future AWS / Azure Support)

**Current State (MVP)**: GCP-optimized implementation
**Future State (Phase 3+)**: Multi-cloud support (AWS, Azure)

To make porting to AWS/Azure straightforward, we design with abstraction layers **now**, even though MVP uses GCP:

### Abstraction Layers to Implement

```python
# MVP Implementation Detail
├── logs/
│   ├── gcp_logger.py (Cloud Logging API)
│   ├── aws_logger.py (CloudWatch - added Phase 3)
│   ├── azure_logger.py (Azure Monitor - added Phase 3)
│   └── logger_interface.py (Abstract base class)
│
├── metrics/
│   ├── gcp_metrics.py (Cloud Monitoring API)
│   ├── aws_metrics.py (CloudWatch - added Phase 3)
│   └── metrics_interface.py (Abstract base class)
│
├── state_store/
│   ├── firestore_store.py (Firestore - MVP)
│   ├── dynamodb_store.py (DynamoDB - Phase 3)
│   ├── cosmos_store.py (Cosmos DB - Phase 3)
│   └── state_interface.py (Abstract base class)
│
└── llm/
    ├── claude_client.py (Anthropic Claude)
    ├── gemini_client.py (Vertex AI Gemini)
    └── llm_interface.py (Abstract base class)
```

### Design Pattern for Multi-Cloud

**Current (GCP-Only)**:
```python
# In cloud_factory.py
logger = GCPLogger(project_id=config.gcp_project)
metrics = GCPMetrics(project_id=config.gcp_project)
state_store = FirestoreStore(project_id=config.gcp_project)

alert_processor = AlertProcessor(
    logger=logger,
    metrics=metrics,
    state_store=state_store
)
```

**Future (Multi-Cloud)**:
```python
# In cloud_factory.py - same code, different implementations
cloud_provider = config.CLOUD_PROVIDER  # "gcp" | "aws" | "azure"

if cloud_provider == "gcp":
    logger = GCPLogger(project_id=config.gcp_project)
    metrics = GCPMetrics(project_id=config.gcp_project)
    state_store = FirestoreStore(project_id=config.gcp_project)
elif cloud_provider == "aws":
    logger = AWSLogger(region=config.aws_region)
    metrics = AWSMetrics(region=config.aws_region)
    state_store = DynamoDBStore(region=config.aws_region)
elif cloud_provider == "azure":
    logger = AzureLogger(resource_group=config.azure_rg)
    metrics = AzureMetrics(resource_group=config.azure_rg)
    state_store = CosmosDBStore(connection_string=config.cosmos_string)

alert_processor = AlertProcessor(
    logger=logger,
    metrics=metrics,
    state_store=state_store
)
```

**MVP Action**: Design with these interfaces from Week 1, even if we only implement GCP versions. This ensures Phase 3 AWS/Azure port takes 2-3 weeks, not 2-3 months.

---

## LLM Model Selection & Benchmarking Strategy

### The Decision: Claude vs Gemini 2.5 Pro

For MVP, we will benchmark BOTH models in Week 1 and select the winner based on production performance metrics.

**Why Benchmark Both**:
- Claude has proven track record in agentic systems
- Gemini 2.5 Pro has 1M token context window (vs Claude's 200K) → could eliminate truncation needs
- Significant cost differences: need to understand unit economics
- GCP-native advantage for Gemini (Vertex AI integration is seamless)

**Benchmarking Matrix** (Week 1 Prototype):

| Metric | Claude Sonnet | Gemini 2.5 Pro | Winner Determines |
|--------|---------------|----------------|-------------------|
| **Cost per 1M tokens** | $3 input / $15 output | ~$1.25 input / $5 output | Economics feasibility |
| **Avg latency (RCA generation)** | <3s | <4s | SLA feasibility |
| **Context window usage** | Hits 4K token limit, requires truncation | Can use 50K tokens, less truncation | Analysis depth |
| **Accuracy (team assignment)** | Baseline | Baseline | Classification quality |
| **RCA confidence scores** | Baseline | Baseline | Recommendation reliability |
| **Hallucination rate** | Baseline | Baseline | Trust/safety |

**Benchmarking Dataset**:
- 100 real pod crash logs from early customer (or synthetic if unavailable)
- Measure: accuracy, latency, cost, token usage
- Success criteria: Either model achieves >85% team assignment accuracy

**Timeline**:
- Week 1: Set up both model endpoints, run benchmarks
- End of Week 1: Make final selection based on data
- Weeks 2-4: Use selected model for MVP

**Fallback Decision**: If benchmarks are too close to call, default to **Claude Sonnet** (proven in production agentic systems).

**Phase 2 Flexibility**: After MVP launch, we can re-benchmark and switch models if customer feedback suggests Gemini is superior.

---

### Decision 1: Team Routing is DETERMINISTIC, Not LLM-Driven

**What We're NOT Doing**: 
❌ Sending alert metadata to Claude and asking "which team should own this?"

**Why Not**:
- Non-deterministic (Claude might assign differently on retry)
- Wasteful (paying LLM tokens for a simple lookup)
- Slow (adds 1-2 seconds latency)
- Unmaintainable (routing logic buried in LLM outputs, hard to audit/change)

**What We ARE Doing**:
✅ Static regex rules in Firestore config:
```yaml
team_routing_rules:
  - pattern: "service:payment-*"
    assigned_team: "payment-platform"
    confidence: 1.0
  
  - pattern: "service:auth-*"
    assigned_team: "identity-platform"
    confidence: 1.0
  
  - pattern: "category:Database.*"
    assigned_team: "data-infrastructure"
    confidence: 1.0
  
  - pattern: "*"  # Fallback
    assigned_team: "platform-infra"
    confidence: 1.0
```

**Benefits**:
- ✅ Deterministic (same alert always gets same team)
- ✅ Fast (<1ms lookup, no LLM)
- ✅ Auditable (routing logic is code-reviewable)
- ✅ Customizable (customers change rules in config, no redeployment)
- ✅ Accurate (regex matches what actually matters)

**The LLM's Job**: Generate RCA and recommendations, NOT routing decisions.

---

### Decision 2: Log Sanitization Happens BEFORE LLM, Not During

**What We're NOT Doing**:
❌ "Claude, analyze these logs but ignore any secrets you find"

**Why Not**:
- Unreliable (Claude might accidentally include secrets in response)
- Risk (secrets are already in Claude's context window)
- Compliance violation (PII/secrets sent to external API)

**What We ARE Doing**:
✅ Deterministic regex sanitizer removes secrets BEFORE any LLM call:
```python
sanitized_logs = sanitizer.clean(raw_logs)
# Scrub: API_KEY=X → API_KEY=[REDACTED]
# Scrub: password=Y → password=[REDACTED]
# Scrub: Bearer token Z → Bearer [REDACTED]
response = claude.analyze(sanitized_logs)  # Safe
```

**Benefits**:
- ✅ Secrets never reach external API
- ✅ Compliance-safe (PII/credentials remain on-prem)
- ✅ Cost savings (shorter context = fewer tokens)
- ✅ Deterministic (same logs always sanitized same way)

---

### Decision 3: Alert De-Duplication Happens BEFORE LLM, Not After

**What We're NOT Doing**:
❌ Call LLM for each of 50 crash alerts, deduplicate tickets afterward

**Why Not**:
- 50x token cost
- 50x slower
- Creates ticket spam until deduplication catches up

**What We ARE Doing**:
✅ Firestore group check before ANY LLM invocation:
```python
group_exists = firestore.get(alert_group_id)
if group_exists:
    # Already analyzed this incident
    increment_counter()
    return  # SKIP LLM ENTIRELY
else:
    # NEW incident
    create_group()
    run_llm()  # Only once per incident
```

**Benefits**:
- ✅ 99% reduction in LLM calls (from 50 to 1)
- ✅ 99% cost reduction per incident
- ✅ Instant response for repeated alerts
- ✅ Clean tickets (no spam)

---

## Open Questions for Implementation

1. **Claude Sonnet vs. Opus**: Should we default to Sonnet (faster, cheaper) or Opus (more capable)? 
   - **Recommendation**: Start with Sonnet. It's 3x cheaper and 2x faster. Upgrade to Opus if accuracy drops below 80%.

2. **Log Truncation Aggressiveness**: How many lines is safe? 50? 100? 200?
   - **Recommendation**: Start with 100 lines. Monitor token usage. If >4K tokens, truncate to 50.

3. **De-Duplication TTL**: How long should an alert group stay active? 30min? 60min? Until manually resolved?
   - **Recommendation**: 60 minutes + auto-cleanup. If no new alerts for 60min, mark resolved and delete from Firestore.

4. **Confidence Thresholds**: At what confidence should we generate recommendations vs. escalate?
   - **Recommendation**: Generate if confidence >= 70%. Show confidence score in Jira. Flag <70% for manual review.

5. **Customer Taxonomy**: Do customers define categories upfront, or should we infer from historical tickets?
   - **Recommendation**: Start with generic taxonomy (Infrastructure, Application, Database, Network). Customers can override in config.

6. **Cost Target**: What's acceptable cost per incident?
   - **Recommendation**: Target <$0.50/incident. At scale (1000 incidents/day), that's <$500/day operational cost.

---

## Appendix A: Example Incident Output

**Input Alert**:
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
  "metric_value": 5
}
```

**Generated Incident**:
```json
{
  "incident_id": "inc-20260604-001",
  "incident_source": "payment-service pod crash",
  "classification": {
    "category": "Infrastructure.Compute.ContainerCrash",
    "severity": "critical",
    "assigned_team": "payment-platform",
    "confidence": 0.92
  },
  "analysis": {
    "summary": "payment-service container was OOMKilled (memory limit 2GB exceeded) after deploying v1.45.2. Memory usage shows linear growth pattern typical of memory leak.",
    "root_cause": "Memory leak introduced in v1.45.2. Container reached 2.1GB (105% of limit) causing OOMKill.",
    "contributing_factors": [
      "Deployment of v1.45.2 happened 5 minutes before first crash (timestamps match)",
      "Memory usage was stable at 800MB-1GB in v1.44.1, now 1.2GB-2.1GB in v1.45.2",
      "Traffic volume unchanged, ruling out load increase"
    ],
    "evidence": {
      "deployment_correlation": {
        "deployed_version": "v1.45.2",
        "deployment_timestamp": "2026-06-04T14:18:30Z",
        "first_crash_timestamp": "2026-06-04T14:23:45Z",
        "time_delta_minutes": 5
      },
      "memory_metrics": {
        "baseline_v1.44.1": "~900MB avg, 1.1GB peak",
        "current_v1.45.2": "linear growth from 1.2GB to 2.1GB over 20 minutes",
        "pattern": "consistent leak, not spike"
      },
      "log_excerpt": "2026-06-04T14:23:40Z ERROR Cannot allocate memory in pool_allocator.rs:234"
    }
  },
  "recommendations": [
    {
      "priority": 1,
      "action": "IMMEDIATE: Increase container memory limit from 2GB to 3GB",
      "rationale": "Stop OOMKill errors immediately while investigating root cause",
      "risks": "Masks underlying memory leak if not fixed in parallel. Only temporary fix.",
      "estimated_mttr_reduction": "5 minutes (immediate stability)"
    },
    {
      "priority": 2,
      "action": "URGENT: Investigate memory leak in v1.45.2 (vs v1.44.1)",
      "rationale": "Linear memory growth in logs points to classic memory leak pattern. Likely in pool_allocator.rs based on error message.",
      "suggested_approach": "Compare memory profiling data between versions, check for unreleased resources in request handling.",
      "estimated_mttr_reduction": "15-30 minutes (permanent fix)"
    },
    {
      "priority": 3,
      "action": "ROLLBACK: If memory still increases after limit adjustment, rollback to v1.44.1",
      "rationale": "v1.44.1 was stable for 48 hours with <1.1GB peak memory",
      "effort": "low",
      "estimated_mttr_reduction": "5 minutes"
    }
  ],
  "links": {
    "gcp_logs_url": "https://console.cloud.google.com/logs/query?project=customer-project&query=...",
    "gcp_metrics_dashboard": "https://console.cloud.google.com/monitoring/dashboards/custom/...",
    "github_commit_v1.45.2": "https://github.com/customer/payment-service/commit/abc123def456",
    "github_diff_v1.44.1_to_v1.45.2": "https://github.com/customer/payment-service/compare/v1.44.1...v1.45.2"
  },
  "metadata": {
    "agent_model": "claude-sonnet-4-20250514",
    "analysis_timestamp": "2026-06-04T14:23:55Z",
    "analysis_duration_seconds": 3.2,
    "tools_called": ["query_gcp_logs", "query_gcp_metrics", "get_recent_deployments", "fetch_source_code"],
    "confidence_score": 0.92
  }
}
```

**Generated Jira Ticket**:
```
Title: 🚨 CRITICAL: payment-service Pod Crash - Memory Leak in v1.45.2

Type: Incident
Priority: Critical
Assigned to: payment-platform team lead
Labels: incident, sre, automated, payment-service, memory-leak, deployment

Description:

## Incident Summary
- **Service**: payment-service
- **Environment**: production
- **Detected**: 2026-06-04 14:23:45 UTC
- **Status**: CrashLoopBackOff (5 restarts)

## Root Cause Analysis
Memory leak introduced in v1.45.2. Container reached 2.1GB (105% of 2GB limit), triggering OOMKill.

**Key Evidence**:
- Deployment v1.45.2 occurred 5 minutes before crash
- Memory usage: 900MB (v1.44.1) → 2.1GB (v1.45.2)
- Linear growth pattern in logs: "ERROR Cannot allocate memory in pool_allocator.rs:234"
- Traffic volume stable (rules out load increase)

## Recommendations (Priority Order)

### 1. ⚡ IMMEDIATE (Do First)
**Action**: Increase container memory limit from 2GB to 3GB
**Why**: Stop OOMKill errors immediately while investigating
**How**: Update k8s deployment manifest, apply `kubectl apply -f payment-service-deployment.yaml`
**Risk**: Temporary fix only—masks underlying leak if not fixed in parallel
**Expected Outcome**: Pod should stabilize within 2 minutes

### 2. 🔍 URGENT (Do in Parallel)
**Action**: Investigate memory leak in v1.45.2
**Where to Look**: `pool_allocator.rs` (from error log)
**How**: Compare memory profiles between v1.44.1 and v1.45.2, look for unreleased resources in request handling
**Expected Duration**: 15-30 minutes
**Expected Outcome**: Permanent fix identified

### 3. 🔄 BACKUP PLAN
**Action**: If memory still increases after limit adjustment, rollback to v1.44.1
**Why**: v1.44.1 was stable for 48 hours, peak 1.1GB
**How**: `git revert <commit-for-v1.45.2>` and redeploy
**Duration**: 5 minutes
**Risk**: Loss of any features added in v1.45.2 (see git diff below)

## Supporting Links
- **GCP Logs**: [Cloud Logging Query](https://console.cloud.google.com/logs/query?project=...)
- **GCP Metrics**: [Memory Usage Dashboard](https://console.cloud.google.com/monitoring/dashboards/custom/...)
- **Code Comparison**: [v1.44.1 vs v1.45.2 Diff](https://github.com/customer/payment-service/compare/v1.44.1...v1.45.2)
- **Deployment Info**: v1.45.2 deployed 2026-06-04 14:18:30 UTC

## Next Steps
- [ ] Apply memory limit increase (1 minute)
- [ ] Monitor memory usage for 10 minutes (confirm stabilization)
- [ ] Investigate memory leak in parallel
- [ ] Test permanent fix in staging before prod deployment
- [ ] Update release notes if leak was due to known issue

---

*This incident was auto-generated by Agentic SRE Platform. Review all recommendations before executing. Contact platform-support if analysis seems incorrect.*
```

---

## Document Approval

| Role | Name | Status | Date |
|------|------|--------|------|
| Product Owner | TBD | Pending | |
| Engineering Lead | TBD | Pending | |
| Security Lead | TBD | Pending | |

---

**Document History**:
- v1.0 (2026-06-04): Initial PRD, ready for design review

