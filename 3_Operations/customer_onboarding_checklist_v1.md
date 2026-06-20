# Agentic SRE Platform - Customer Onboarding Checklist v1.0

**Customer Name**: ___________________________  
**Date Started**: ___________________________  
**Assigned Engineer**: ___________________________  
**Expected Completion**: ___________________________  

---

## Pre-Onboarding (Engineer Preparation)

### Step 0: Preparation Phase (1-2 hours before customer call)

- [ ] **Verify customer details**
  - [ ] Customer name and organization
  - [ ] Primary contact email
  - [ ] GCP project ID(s)
  - [ ] Jira workspace URL
  - [ ] GitHub organization

- [ ] **Create Firestore customer record**
  ```
  Firestore collection: customers
  Document ID: [customer-slug]
  
  Fields to populate:
  - customer_id
  - name
  - gcp_project_id
  - jira_workspace_url
  - github_organization
  - created_at
  - status: "onboarding"
  ```

- [ ] **Prepare demo environment**
  - [ ] Cloud Run service deployed to staging
  - [ ] Sample pod crash scenario ready
  - [ ] Webhook URL ready to share: `https://agentic-sre-staging.run.app/alerts/ingest`
  - [ ] Demo Jira project created or designated

- [ ] **Document links prepared**
  - [ ] GitHub App setup guide link
  - [ ] Jira API token creation guide link
  - [ ] Team routing rules template
  - [ ] Support email and Slack channel

---

## Week 1: Initial Setup

### Phase 1A: Discovery Call (30 minutes)

**Attendees**: Customer (Ops Lead), Engineer (Agentic SRE Team)

**Agenda**:
- [ ] **Welcome & overview** (5 min)
  - "We're reducing your incident triage time from 20+ minutes to <2 minutes"
  - "This MVP focuses on pod crashes; we'll expand to other incident types later"

- [ ] **Demo the MVP** (10 min)
  - Show pod crash → Jira ticket flow
  - Highlight: RCA, recommendations, team routing
  - Explain: "This analysis used to take your L1 engineer 20 minutes. The agent does it in 30 seconds."

- [ ] **Understand their setup** (10 min)
  - "Which GCP projects do we monitor?"
  - "How many services? Which ones are most critical?"
  - "Who owns incidents? How are they routed today?"
  - "What incident types cause the most pain?"

- [ ] **Next steps alignment** (5 min)
  - "Week 1: GitHub App setup + Jira credentials"
  - "Week 2: Team routing rules configuration"
  - "Week 3: First incident live"

**Output**: 
- [ ] Customer authorization to proceed
- [ ] GCP project IDs confirmed
- [ ] GitHub organization name confirmed
- [ ] Jira workspace confirmed

---

### Phase 1B: GitHub App Setup (1-2 hours)

**Customer Self-Service** (or Engineer assists):

**Step 1: Create GitHub App**
- [ ] Customer navigates to: `https://github.com/organizations/[ORG]/settings/apps`
- [ ] Click "New GitHub App"
- [ ] Fill in:
  ```
  App name: Agentic SRE
  Homepage URL: https://agentic-sre.platform.com
  Webhook URL: https://agentic-sre-staging.run.app/github-webhook (if needed later)
  Webhook active: Unchecked (for MVP, not needed)
  ```
- [ ] Set Permissions (CRITICAL - minimal access):
  ```
  Repository permissions:
  - Contents: Read-only
  - Metadata: Read-only
  
  Organization permissions:
  - None
  
  User permissions:
  - None
  ```
- [ ] Click "Create GitHub App"

**Step 2: Install GitHub App to Repositories**
- [ ] Go to "Install App" in left sidebar
- [ ] Select repositories to grant access:
  ```
  RECOMMENDED: Only select critical services
  Example: payment-service, auth-service, order-service
  
  AVOID: Giving access to entire organization (supply chain risk)
  ```
- [ ] Customer selects: payment-service, auth-service
- [ ] Click "Install & Authorize"

**Step 3: Generate Private Key**
- [ ] Go back to GitHub App settings
- [ ] Scroll to "Private keys" section
- [ ] Click "Generate a private key"
- [ ] Save the `.pem` file **securely** (never commit to Git)
- [ ] Note the App ID and Installation ID

**Step 4: Share Credentials with Agentic SRE**
- [ ] Customer provides (via secure channel):
  ```
  App ID: [12345]
  Installation ID: [67890]
  Private Key: [-----BEGIN RSA PRIVATE KEY-----...]
  Allowed Repos: [payment-service, auth-service]
  ```
- [ ] Engineer stores in Firestore (encrypted):
  ```
  Firestore: customers > [customer-id]
  Field: credentials.github_app
  {
    "app_id": "12345",
    "installation_id": "67890",
    "private_key": "[ENCRYPTED_AES256]",
    "allowed_repos": ["payment-service", "auth-service"]
  }
  ```

**Verification**:
- [ ] Engineer tests GitHub API with credentials
  ```bash
  curl -X GET https://api.github.com/app/installations/67890 \
    -H "Authorization: Bearer [token]"
  # Should return installation details
  ```

- [ ] [ ] GitHub App setup COMPLETE ✅

---

### Phase 1C: Jira API Token Setup (30 minutes)

**Customer Self-Service**:

**Step 1: Generate Jira API Token**
- [ ] Customer navigates to: `https://id.atlassian.com/manage-profile/security/api-tokens`
- [ ] Click "Create API Token"
- [ ] Label: `Agentic SRE Platform`
- [ ] Copy the token (only shown once)

**Step 2: Share Token with Agentic SRE**
- [ ] Customer provides (via secure channel):
  ```
  Email: [jira-user@company.com]
  API Token: [XXXXXXXXXXXXXXXXXXXX]
  Jira Workspace URL: [https://company.atlassian.net]
  Default Project Key: [INFRA] (where incidents get created)
  ```

- [ ] Engineer stores in Firestore (encrypted):
  ```
  Firestore: customers > [customer-id]
  Field: credentials.jira
  {
    "email": "jira-user@company.com",
    "api_token": "[ENCRYPTED_AES256]",
    "workspace_url": "https://company.atlassian.net",
    "project_key": "INFRA"
  }
  ```

**Verification**:
- [ ] Engineer tests Jira API:
  ```bash
  curl -X GET https://company.atlassian.net/rest/api/3/myself \
    -H "Authorization: Basic [encoded]" \
    -H "Content-Type: application/json"
  # Should return user details
  ```

- [ ] [ ] Jira API setup COMPLETE ✅

---

### Phase 1D: Alert Webhook Configuration (30 minutes)

**Customer Self-Service** (based on their alert system):

**If using GCP Cloud Monitoring**:
- [ ] Go to Cloud Monitoring → Alerting Policies
- [ ] Create notification channel:
  ```
  Type: Webhook
  URL: https://agentic-sre-staging.run.app/alerts/ingest
  Authentication: None (for MVP; add mTLS in Phase 2)
  ```
- [ ] Add to existing alert policies

**If using Prometheus/AlertManager**:
- [ ] Update alertmanager.yml:
  ```yaml
  global:
    resolve_timeout: 5m

  route:
    receiver: 'agentic-sre'

  receivers:
  - name: 'agentic-sre'
    webhook_configs:
    - url: 'https://agentic-sre-staging.run.app/alerts/ingest'
      send_resolved: true
  ```

**If using Datadog**:
- [ ] Go to Monitors → Manage Monitors
- [ ] Edit monitor → Edit notifications
- [ ] Add webhook:
  ```
  @webhook-agentic-sre https://agentic-sre-staging.run.app/alerts/ingest
  ```

**Pub/Sub Fallback Configuration** (CRITICAL for resilience):
- [ ] Customer creates Pub/Sub topic:
  ```
  gcloud pubsub topics create agentic-sre-fallback-alerts
  ```

- [ ] Customer authorizes Agentic SRE service account:
  ```bash
  gcloud pubsub topics add-iam-policy-binding agentic-sre-fallback-alerts \
    --member=serviceAccount:agentic-sre@PROJECT.iam.gserviceaccount.com \
    --role=roles/pubsub.publisher
  ```

- [ ] Customer configures alerting to also send to Pub/Sub topic (as secondary target)

- [ ] [ ] Webhook configuration COMPLETE ✅

---

### Phase 1E: Team Routing Rules Configuration (1-2 hours)

**Engineer Assists**:

**Step 1: Understand Customer's Team Structure**
- [ ] Customer fills out team mapping:
  ```
  Service Name          Owning Team
  ===================================
  payment-service      → payment-platform
  auth-service         → identity-platform
  billing-service      → billing-platform
  api-gateway          → platform-infra
  ```

**Step 2: Create Team Routing Rules YAML**
- [ ] Engineer creates template:
  ```yaml
  team_routing_rules:
    - id: "rule-1"
      pattern: "service:payment-*"
      assigned_team: "payment-platform"
      confidence: 1.0
    
    - id: "rule-2"
      pattern: "service:auth-*"
      assigned_team: "identity-platform"
      confidence: 1.0
    
    - id: "rule-3"
      pattern: "service:*"
      assigned_team: "platform-infra"
      confidence: 0.8
    
    - id: "fallback"
      pattern: "*"
      assigned_team: "on-call"
      confidence: 0.5

  incident_categories:
    - id: "Infrastructure.Compute.ContainerCrash"
      keywords: ["CrashLoopBackOff", "OOMKilled"]
      assigned_team: "platform-infra"
      severity_default: "critical"
  ```

- [ ] Customer reviews and approves

**Step 3: Store in Firestore**
- [ ] Engineer stores config:
  ```
  Firestore: customers > [customer-id]
  Field: team_routing_rules
  [... YAML content ...]
  ```

- [ ] [ ] Team routing rules COMPLETE ✅

---

## Week 2: Testing & Validation

### Phase 2A: Webhook Test (15 minutes)

**Engineer-Led**:

**Step 1: Send Test Alert via curl**
```bash
curl -X POST https://agentic-sre-staging.run.app/alerts/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "alert_id": "test-001",
    "alert_name": "Pod CrashLoopBackOff",
    "severity": "warning",
    "resource_type": "gcp_gke_pod",
    "resource_id": "payment-service-xyz",
    "service_name": "payment-service",
    "timestamp": "2026-06-04T14:23:45Z",
    "metric_name": "container_restart_count",
    "metric_value": 5,
    "labels": {
      "environment": "staging",
      "region": "us-central1"
    }
  }'
```

**Expected Response**:
```json
{
  "status": "accepted",
  "incident_id": "inc-20260604-001",
  "processing_mode": "async"
}
```

**Verification**:
- [ ] Check Cloud Logging: Alert was received and processed
  ```
  Firestore collection "alert_groups" should have new document
  Cloud Logging should show: "Alert received" + "Team routing: payment-platform"
  ```

- [ ] [ ] Webhook test PASSED ✅

---

### Phase 2B: Demo Incident (Real Scenario)

**Engineer-Led** (with Customer observing):

**Scenario: Real or Simulated Pod Crash**

Option A: **Real Pod Crash** (if customer is ready):
- [ ] Trigger actual pod OOMKill in staging
- [ ] Watch incident flow through the platform
- [ ] See Jira ticket created in real-time

Option B: **Simulated** (if real scenario too risky):
- [ ] Pre-recorded incident scenario
- [ ] Show logs, metrics, LLM analysis
- [ ] Create Jira ticket with recommendations

**What Customer Should See**:
- [ ] Alert arrives at webhook
- [ ] Platform de-duplicates (no duplicate tickets)
- [ ] Jira ticket created with:
  - Root cause analysis
  - 2-3 recommendations
  - Links to logs and metrics
  - Team assignment correct
- [ ] **Customer feedback**: "Did the routing work? Did the RCA make sense?"

- [ ] [ ] Demo incident COMPLETE ✅

---

### Phase 2C: Runbook Walkthrough (15 minutes)

**Engineer-Led**:

**Customer learns**:
- [ ] How to view incidents in Jira
- [ ] How to update team routing rules
- [ ] How to check Cloud Logging for issues
- [ ] How to reach support (Slack/email)
- [ ] Emergency fallback: What if webhook fails?

**Customer gets**:
- [ ] Printed runbook
- [ ] Access to Slack support channel
- [ ] On-call engineer contact info

- [ ] [ ] Runbook walkthrough COMPLETE ✅

---

## Week 3: Go-Live

### Phase 3A: Production Webhook Switch (30 minutes)

**Customer-Driven** (Engineer confirms):

- [ ] Customer updates webhook URL from staging to production:
  ```
  FROM: https://agentic-sre-staging.run.app/alerts/ingest
  TO:   https://agentic-sre.run.app/alerts/ingest
  ```

- [ ] Customer tests with single alert:
  ```bash
  curl -X POST https://agentic-sre.run.app/alerts/ingest \
    -H "Content-Type: application/json" \
    -d '[... same test alert ...]'
  ```

- [ ] Engineer confirms:
  - [ ] Alert reached production service
  - [ ] Processing succeeded
  - [ ] Firestore has customer's data
  - [ ] Team routing rules loaded correctly

- [ ] [ ] Production webhook ACTIVATED ✅

---

### Phase 3B: First Live Incident (24-hour monitoring)

**Customer with Engineer on-call**:

**What to expect**:
- [ ] First real incident comes in
- [ ] Ticket created automatically
- [ ] Customer reviews quality of RCA
- [ ] Customer implements recommendation (if applicable)
- [ ] Engineer observes and supports

**Feedback questions** (engineer asks):
- [ ] Was the team assignment correct?
- [ ] Did the RCA help you understand the issue faster?
- [ ] Were the recommendations actionable?
- [ ] Would you have done anything differently?

- [ ] [ ] First incident GO-LIVE ✅

---

### Phase 3C: SLA Verification (1 week)

**Engineer monitors**:

- [ ] Alert to ticket latency < 30 seconds ✓
- [ ] Team assignment accuracy > 85% ✓
- [ ] Zero false positives (no wrong tickets) ✓
- [ ] System uptime > 99% ✓

**Customer provides feedback**:
- [ ] "Did this save you time vs. manual triage?"
- [ ] "Would you change anything about the team routing?"
- [ ] "Should we process other incident types?"

- [ ] [ ] SLA verification COMPLETE ✅

---

## Final Checklist

### Sign-Off

**Customer**:
- [ ] Confirms system is working as expected
- [ ] Commits to 1-month trial period (minimum)
- [ ] Provides feedback channel (weekly sync recommended)

**Engineer**:
- [ ] Confirms all systems deployed and operational
- [ ] Confirms customer can operate independently
- [ ] Confirms runbook is clear and complete
- [ ] Schedules 1-week check-in

**Agentic SRE Team**:
- [ ] Customer onboarding documented in Firestore
- [ ] Metrics dashboard showing customer's incidents
- [ ] Customer feedback logged
- [ ] Post-mortem (if any issues) documented

---

## Troubleshooting Guide

### Problem: Webhook Returns 400 Bad Request

**Cause**: Alert payload doesn't match schema

**Fix**:
1. Check alert JSON matches required fields:
   ```json
   {
     "alert_id": "string",
     "alert_name": "string",
     "severity": "critical|warning|info",
     "resource_type": "gcp_gke_pod",
     "resource_id": "string",
     "service_name": "string",
     "timestamp": "RFC3339",
     "metric_name": "string",
     "metric_value": "number",
     "labels": {...}
   }
   ```
2. Check timestamp is RFC3339 format: `2026-06-04T14:23:45Z`
3. Re-send test alert

---

### Problem: Team Assignment Wrong

**Cause**: Team routing rule doesn't match alert

**Fix**:
1. Review alert's `service_name` field
2. Check regex pattern in Firestore rules
3. Test pattern manually:
   ```python
   import re
   pattern = "service:payment-*"
   service = "payment-service"
   regex = pattern.replace("*", ".*")
   if re.match(regex, service):
       print("MATCH!")
   ```
4. Update routing rule if needed

---

### Problem: Jira Ticket Not Created

**Cause**: Jira API token expired or invalid

**Fix**:
1. Verify API token is still valid (go to Atlassian settings)
2. Generate new token if needed
3. Update Firestore credentials
4. Test Jira API:
   ```bash
   curl -X GET https://company.atlassian.net/rest/api/3/myself \
     -H "Authorization: Basic [encoded]" \
     -H "Content-Type: application/json"
   ```

---

### Problem: GitHub App Can't Fetch Source Code

**Cause**: Token expired or insufficient permissions

**Fix**:
1. Verify GitHub App still has "Contents: Read-only" permission
2. Check App is still installed on repository
3. Regenerate private key if needed
4. Test GitHub API

---

## Support Contacts

**Agentic SRE Team**:
- Slack: #agentic-sre-support
- Email: support@agentic-sre.platform.com
- On-Call: [phone number]
- Hours: 9 AM - 6 PM PT, Mon-Fri

**Escalation**:
- Critical issue (no incidents being processed): Page on-call
- Integration issue (GitHub/Jira): Email support
- Feature request: Slack #agentic-sre-feedback

---

**Onboarding Complete!** 🎉

Your Agentic SRE platform is live. Start monitoring incidents and reducing L1 triage time.

