# Agentic SRE Platform - On-Call Runbook v1.0

**Last Updated**: June 2026  
**Owner**: Platform Engineering Team  
**On-Call Rotation**: [Link to on-call schedule]

---

## Quick Start (First 5 Minutes)

### You've Been Paged. Now What?

1. **Check Slack alert**
   - Go to #agentic-sre-alerts
   - Look for severity: CRITICAL, WARNING, or INFO

2. **Acknowledge the page**
   - Open PagerDuty (or your on-call tool)
   - Click "Acknowledge Incident"
   - Add note: "Looking into it"

3. **Check the dashboard**
   - Open [link to Cloud Monitoring dashboard]
   - Look for RED indicators

4. **If you need to act immediately, jump to**:
   - [Cloud Run is down](#scenario-cloud-run-is-down)
   - [Firestore is erroring](#scenario-firestore-errors)
   - [Alerts are piling up](#scenario-alerts-are-piling-up)

---

## System Overview (2-minute version)

### What is this system?

The Agentic SRE Platform automatically triages pod crash incidents:

```
Customer Alert → Our Webhook → De-dupe & Route → LLM Analysis → Jira Ticket
```

### Key components:

| Component | Hosted On | Criticality | If Down |
|-----------|-----------|------------|---------|
| Alert Webhook | Cloud Run | CRITICAL | Pub/Sub buffer catches alerts (48hr retention) |
| Firestore | Managed | CRITICAL | All alerts fail; requires manual recovery |
| LLM (Claude) | Anthropic API | HIGH | Fall back to basic analysis template |
| Jira Integration | HTTPS API | HIGH | Queue to Cloud Tasks; manual retry later |
| Cloud Logging | Managed | MEDIUM | Loss of audit trail; continue operating |

### Healthy system looks like:

```
Cloud Logging shows:
- 10-50 alerts/min processed
- 100-500 incidents/day created
- P95 latency: <3 seconds
- Error rate: <0.1%
```

---

## Monitoring Dashboard Checks

### Step 1: Open the dashboard

**Link**: [Cloud Monitoring Dashboard](https://console.cloud.google.com/monitoring/dashboards/custom/agentic-sre-main?project=[PROJECT])

### Step 2: Look for RED

| Metric | Healthy | ALERT | ACTION |
|--------|---------|-------|--------|
| **Cloud Run Uptime** | > 99.9% | < 99% | See: [Cloud Run is down](#scenario-cloud-run-is-down) |
| **Alert Ingestion Rate** | 10-50/min | 0 (no alerts) | See: [Webhook receiver failed](#scenario-webhook-receiver-failing) |
| **Incident Creation Rate** | 100-500/day | 0 | See: [Jira integration failed](#scenario-jira-integration-failed) |
| **P95 Latency** | <3s | >5s | See: [Slow response times](#scenario-slow-response-times) |
| **Error Rate** | <0.1% | >1% | See: [High error rate](#scenario-high-error-rate) |
| **Firestore Latency** | <100ms | >500ms | See: [Firestore performance degradation](#scenario-firestore-degradation) |

---

## Common Scenarios & Fixes

### Scenario: Cloud Run is Down

**Detection**:
- Cloud Run service showing "Unhealthy"
- Dashboard: Cloud Run Uptime = 0%
- Slack: Multiple "webhook timeout" alerts from customers

**Immediate Action** (< 2 minutes):

1. **Check Cloud Run status**:
   ```bash
   gcloud run services describe agentic-sre-agent --region=us-central1
   ```

2. **Check recent deployments**:
   ```bash
   gcloud run services describe agentic-sre-agent \
     --region=us-central1 --format='value(status)'
   ```

3. **Check if service crashed**:
   - Open Cloud Logging
   - Filter: `resource.type="cloud_run_revision" AND severity="ERROR"`
   - Look for crash logs

4. **Check if quota exceeded**:
   - Open Cloud Run → Quotas
   - Are we at limit for concurrent requests?

**Recovery Steps**:

**Option A: Service crashed (logs show errors)**
```bash
# Redeploy the service
gcloud run deploy agentic-sre-agent \
  --image=gcr.io/[PROJECT]/agentic-sre:latest \
  --region=us-central1 \
  --memory=2Gi \
  --timeout=60
```

**Option B: Quota exceeded**
```bash
# Increase max instances
gcloud run services update agentic-sre-agent \
  --region=us-central1 \
  --max-instances=100
```

**Option C: OOM (Out of Memory)**
```bash
# Increase memory allocation
gcloud run services update agentic-sre-agent \
  --region=us-central1 \
  --memory=4Gi
```

**Step 5: Verify recovery**
```bash
# Send test alert
curl -X POST https://agentic-sre.run.app/alerts/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "alert_id": "test-$(date +%s)",
    "alert_name": "Test Alert",
    "severity": "info",
    "resource_type": "gcp_gke_pod",
    "resource_id": "test-pod",
    "service_name": "test-service",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "metric_name": "test",
    "metric_value": 1,
    "labels": {"environment": "prod"}
  }'
```

Expected response: `200 OK` with `incident_id`

**When to escalate**:
- If service keeps crashing after redeploy
- If quota can't be increased
- If memory still not enough

**Escalation**: Page the Platform Engineering Lead

---

### Scenario: Firestore Errors

**Detection**:
- Cloud Logging shows: `PERMISSION_DENIED` or `RESOURCE_EXHAUSTED`
- Jira tickets not being created
- Alert groups not being stored

**Immediate Action** (< 2 minutes):

1. **Check Firestore quota**:
   ```bash
   gcloud firestore describe --database="(default)"
   ```

2. **Check service account permissions**:
   ```bash
   gcloud projects get-iam-policy [PROJECT] \
     --flatten="bindings[].members" \
     --filter="bindings.members:serviceAccount:agentic-sre@[PROJECT].iam.gserviceaccount.com"
   ```

3. **Check recent Firestore operations**:
   - Open Cloud Logging
   - Filter: `resource.type="cloud_firestore" AND severity="ERROR"`

**Recovery Steps**:

**Option A: Firestore quota exceeded**
```bash
# Check quota usage
gcloud firestore describe

# Request quota increase (go to Cloud Console)
# Firestore → Settings → Quotas
# Click "Request quota increase"
```

**Option B: Service account missing permissions**
```bash
# Grant required permissions
gcloud projects add-iam-policy-binding [PROJECT] \
  --member=serviceAccount:agentic-sre@[PROJECT].iam.gserviceaccount.com \
  --role=roles/datastore.user
```

**Option C: Database is temporarily down**
```bash
# Check database status
gcloud firestore describe --database="(default)"

# If status is "UPDATING" or "DELETING", wait for it to complete
# (This is rare and handled by Google)
```

**When to escalate**:
- If quota is very high but still hitting limits
- If permissions are correct but still failing
- If errors persist after 30 minutes

**Escalation**: File a GCP support ticket (Premium support recommended)

---

### Scenario: Webhook Receiver Failing

**Detection**:
- Alert ingestion rate drops to 0
- Cloud Logging shows: `webhook_receiver crashed` or `connection refused`
- Customers report webhooks timing out

**Immediate Action** (< 2 minutes):

1. **Check Cloud Run logs**:
   ```bash
   gcloud logging read \
     "resource.type=cloud_run_revision AND severity=ERROR" \
     --limit=10
   ```

2. **Look for patterns**:
   - "Address already in use" → Port conflict
   - "Out of memory" → Need more RAM
   - "Unmarshal error" → Bad request format

**Recovery Steps**:

**Option A: Port conflict**
```bash
# Restart Cloud Run service
gcloud run services update agentic-sre-agent \
  --region=us-central1 \
  --no-traffic-split  # Drain traffic first

# Wait 30 seconds, then re-enable
gcloud run services update-traffic agentic-sre-agent \
  --to-latest \
  --region=us-central1
```

**Option B: Out of memory**
```bash
# Increase memory
gcloud run services update agentic-sre-agent \
  --region=us-central1 \
  --memory=4Gi
```

**Option C: Bad request format**
```bash
# Check if alert schema changed
# Review recent customer config changes
# May need to update validation logic
```

**When to escalate**:
- If issue persists after restart
- If we need to roll back a deployment

**Escalation**: Page the Platform Engineering Lead

---

### Scenario: Alerts Are Piling Up

**Detection**:
- Pub/Sub fallback queue has 10,000+ messages
- Alert ingestion rate normal, but incident creation rate dropping
- Cloud Logging shows processing backlog

**Immediate Action** (< 2 minutes):

1. **Check Cloud Tasks queue**:
   ```bash
   gcloud tasks queues list
   gcloud tasks list --queue=agentic-sre-incidents
   ```

2. **Check Jira API status**:
   ```bash
   curl -X GET https://company.atlassian.net/rest/api/3/myself \
     -H "Authorization: Basic [encoded]" \
     -H "Content-Type: application/json"
   ```

3. **Check LLM (Claude) API status**:
   ```bash
   # Check recent API call latency in Cloud Logging
   # Look for slow responses or rate limiting
   ```

**Recovery Steps**:

**Option A: Jira API is down**
```bash
# Verify Jira status page: https://status.atlassian.com/

# If Jira is up but our calls are failing:
# - Check credentials in Firestore
# - Verify API token hasn't expired
# - Check project permissions

# Manually update Firestore credentials if needed
```

**Option B: Claude API is rate limited**
```bash
# Check Anthropic status: https://status.anthropic.com/

# If rate limited:
# - Slow down incident creation (add 1-second delay)
# - Batch requests if possible
# - Contact Anthropic support for higher limits
```

**Option C: Cloud Tasks backlog is stuck**
```bash
# Purge stuck Cloud Tasks
gcloud tasks queues purge agentic-sre-incidents --queue-location=us-central1

# Restart Cloud Tasks worker (if applicable)
# This will force reprocessing of failed tasks
```

**When to escalate**:
- If Jira is down (contact Jira support)
- If Claude API is down (contact Anthropic)
- If backlog doesn't clear in 30 minutes

**Escalation**: Notify customers of degradation; Page Platform Engineering Lead

---

### Scenario: Slow Response Times

**Detection**:
- Dashboard P95 latency > 5 seconds (should be < 3s)
- Customer complaints: "It's taking too long to create tickets"
- Cloud Logging shows slow API calls

**Immediate Action** (< 2 minutes):

1. **Identify bottleneck**:
   ```bash
   gcloud logging read \
     "resource.type=cloud_run_revision AND latency_ms > 5000" \
     --limit=10
   ```

2. **Check which service is slow**:
   - Firestore queries? (logs latency in metrics)
   - GCP APIs? (Cloud Logging API, Cloud Monitoring API)
   - LLM (Claude)? (Anthropic API)

**Recovery Steps**:

**Option A: Firestore is slow**
- Check for hot partitions (Firestore dashboard)
- Reduce load temporarily by throttling alert ingestion
- Add caching for frequently-accessed data (e.g., customer configs)

**Option B: GCP APIs are slow**
- Implement client-side caching
- Reduce query frequency (e.g., cache logs for 5 minutes)
- Use batch operations instead of individual calls

**Option C: Claude API is slow**
- Check API status (may be overloaded)
- Reduce context size (truncate logs more aggressively)
- Increase timeout (currently 30s, can go to 60s)

**When to escalate**:
- If latency remains > 5s after optimization
- If customers are complaining about SLA breaches

**Escalation**: File incident, schedule optimization meeting

---

### Scenario: High Error Rate

**Detection**:
- Dashboard: Error Rate > 1%
- Cloud Logging shows: `ERROR` or `EXCEPTION`
- Jira tickets show: Analysis failed or "context quality: degraded"

**Immediate Action** (< 2 minutes):

1. **Categorize errors**:
   ```bash
   # Get error summary
   gcloud logging read \
     "severity=ERROR" \
     --format=table(jsonPayload.error_code, jsonPayload.message) \
     --limit=20
   ```

2. **Find most common error**:
   - Example: `LLM_CONTEXT_TOO_LARGE` (50% of errors)
   - Example: `JIRA_API_FAILED` (30% of errors)
   - Example: `GITHUB_AUTH_FAILED` (20% of errors)

**Recovery Steps**:

**Option A: LLM context too large**
- Implement more aggressive truncation
- Reduce token budget from 4000 to 2000
- Update sanitizer to remove more lines

**Option B: Jira API failures**
- Check API quota (rate limit reset in X minutes)
- Verify credentials are still valid
- Implement retry logic with exponential backoff

**Option C: GitHub authentication failures**
- Check if GitHub Apps still have permissions
- Check if private key hasn't expired
- Notify customers to refresh credentials

**When to escalate**:
- If error rate > 5% for > 10 minutes
- If majority of errors are from external API failures

**Escalation**: Notify customers; Page Platform Engineering Lead

---

### Scenario: Firestore Degradation

**Detection**:
- Firestore latency > 500ms (should be < 100ms)
- Dashboard shows slow reads/writes
- Cloud Logging shows `DEADLINE_EXCEEDED`

**Immediate Action** (< 2 minutes):

1. **Check Firestore activity**:
   ```bash
   # Open Firestore dashboard
   # Look for: Biggest indices, Most reads, Most writes
   ```

2. **Check for hot partitions**:
   - Is alert_groups collection getting hammered?
   - Is incidents collection growing too fast?

**Recovery Steps**:

**Option A: Too many reads/writes**
- Implement in-memory caching (Redis or Python @lru_cache)
- Cache customer configs (updated infrequently)
- Cache alert groups for 1 minute

**Option B: Indexes missing**
- Check Firestore → Indexes
- Add composite index if needed:
  ```
  Collection: alert_groups
  Filters: service_name, environment
  Sort: last_occurrence DESC
  ```

**Option C: Database size too large**
- Delete old incidents (older than 90 days)
- Archive alert groups after they're resolved
- Enable TTL for auto-deletion

**When to escalate**:
- If latency remains > 500ms after caching
- If need to request larger quotas from Google

**Escalation**: File quota increase request; Page Database DBA

---

## Emergency Procedures

### Break Glass: Cloud Run is Down for > 5 Minutes

**When to use**: Platform is completely unavailable, customers are losing incidents

**Steps**:

1. **Notify customers immediately**:
   ```
   Slack #agentic-sre-customers:
   "INCIDENT: Agentic SRE Platform is temporarily unavailable. 
   Please send alerts to manual triage process. ETA recovery: 15 minutes."
   ```

2. **Enable manual alert ingestion**:
   - Direct alerts to Pub/Sub fallback topic directly
   - Customers send alerts to: `projects/[PROJECT]/topics/agentic-sre-fallback-alerts`
   - These queue and process once service recovers

3. **Recover Cloud Run**:
   - See [Cloud Run is down](#scenario-cloud-run-is-down)

4. **Process queued alerts**:
   - Once service recovers, process Pub/Sub backlog
   - Should process ~100 alerts/minute

5. **Notify customers**:
   ```
   "Platform recovered. Processing backlog of {N} alerts.
   All incidents will be created shortly. Thank you for your patience."
   ```

---

## Post-Incident Review

**After every incident, do**:

- [ ] **Document what happened**:
  ```
  Incident ID: [INC-001]
  Duration: 15 minutes (14:23 - 14:38)
  Root cause: Cloud Run service crashed due to OOM
  Impact: 150 alerts dropped, 45 customers affected
  ```

- [ ] **Update runbook**:
  - Was there something we could have detected earlier?
  - Should we add a new monitoring alert?
  - Should we change the runbook steps?

- [ ] **File postmortem** (within 24 hours):
  - 5-minute meeting with team
  - What went well?
  - What went wrong?
  - What will we do differently?

---

## Contacts & Escalation

### L1: On-Call Engineer (You)
- **Response time**: Immediate
- **Authority**: Can restart services, purge queues, redeploy
- **When to escalate**: If unsure or > 30 minutes unresolved

### L2: Platform Engineering Lead
- **Response time**: 15 minutes
- **Authority**: Can modify infrastructure, request quota increases
- **Contact**: #agentic-sre-escalations Slack channel

### L3: VP Engineering
- **Response time**: 30 minutes
- **Authority**: Can declare critical incident, notify customers
- **Contact**: Escalate via Platform Engineering Lead

### External Escalation
- **Google Cloud Support**: GCP infrastructure issues (premium account)
- **Anthropic Support**: Claude API issues (contact Anthropic)
- **Atlassian Support**: Jira integration issues (contact Jira)

---

## Key Metrics to Check

**Every 5 minutes** (if paged):
- [ ] Cloud Run uptime
- [ ] Alert ingestion rate
- [ ] Error rate
- [ ] P95 latency

**Every 30 minutes** (if incident ongoing):
- [ ] Firestore read/write latency
- [ ] Cloud Tasks queue depth
- [ ] Jira API response time
- [ ] Customer feedback (Slack, email)

**Every 1 hour** (post-incident):
- [ ] All metrics back to normal
- [ ] No customer complaints
- [ ] System stable for 15 minutes minimum

---

## Useful Links

**Dashboards**:
- [Main Monitoring Dashboard](https://console.cloud.google.com/monitoring/dashboards/custom/agentic-sre-main)
- [Error Log Dashboard](https://console.cloud.google.com/logs)
- [Cloud Run Console](https://console.cloud.google.com/run)

**Configuration**:
- [Cloud Run Service](https://console.cloud.google.com/run/detail/us-central1/agentic-sre-agent)
- [Firestore Database](https://console.cloud.google.com/firestore)
- [Cloud Tasks Queues](https://console.cloud.google.com/cloudtasks)

**Team Communication**:
- Slack: #agentic-sre-alerts, #agentic-sre-escalations
- Email: support@agentic-sre.platform.com
- On-Call Schedule: [Link to schedule]

---

## Notes

**Last updated**: June 2026  
**Last tested**: [Date]  
**Next review**: [Date]  

Questions? Ask in #agentic-sre or reach out to the platform team.

