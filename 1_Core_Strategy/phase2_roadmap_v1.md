# Agentic SRE Platform - Phase 2 Roadmap v1.0

**Timeline**: Q3 2026 - Q1 2027 (8-12 weeks after MVP)  
**Status**: Vision Document (subject to customer feedback)  
**Owner**: Product Engineering Team

---

## Executive Summary

Phase 1 (MVP) proved the core concept: **Automated pod crash triage reduces MTTR by 50%+**.

Phase 2 expands this to become a **comprehensive multi-incident-type platform** running on **GCP, AWS, and Azure**, with **semi-autonomous remediation** capabilities.

**Phase 2 Scope** (prioritized by customer demand):
1. Additional incident types (latency, errors, resource exhaustion)
2. Multi-cloud support (AWS + Azure)
3. Semi-autonomous remediation (with human approval)
4. Customer feedback loops (learning system)
5. Advanced diagnostics (RAG for code search)

---

## Phase 2 Phases (5 iterations)

### Phase 2A: Multi-Incident Types (8 weeks)

**Goal**: Expand beyond pod crashes to handle 80% of real-world incidents

#### 2A.1: High-Latency Incident Detection

**Problem**: APIs respond slowly, users timeout

**What we'll add**:
- P95/P99 latency spike detection
- Correlate with:
  - Downstream service health
  - Database query performance
  - Network latency
  - GC pauses (Java/Go)

**Output**: Diagnose "Why is response time slow?"
- "Database queries increased from 100ms to 500ms → index missing or N+1 query"
- "GC pauses increased 10x → memory leak causing aggressive garbage collection"
- "Downstream service timeout → payment API unreachable"

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: >80% accuracy on 50 test scenarios

---

#### 2A.2: Error Rate Spike Detection

**Problem**: Errors increase suddenly, users see failures

**What we'll add**:
- Error rate change detection (baseline vs current)
- Error type classification (5xx, 4xx, timeouts, exceptions)
- Correlate with:
  - Recent deployments
  - Dependency health
  - Configuration changes

**Output**: Diagnose "Why are we seeing errors?"
- "500 errors spiked after deploy of v1.46 → regression in payment processing"
- "4xx errors from auth service → invalid credentials or API change"
- "Timeout errors → downstream service is slow/unreachable"

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: Correctly identify top 3 error causes

---

#### 2A.3: Resource Exhaustion Detection

**Problem**: Pods run out of CPU, memory, or disk

**What we'll add**:
- Memory/CPU trend analysis
- Correlation with:
  - Traffic volume changes
  - Deployment changes
  - Time-of-day patterns
  - Seasonal patterns

**Output**: Predict "Is this pod about to run out of resources?"
- "Memory growing linearly at 500MB/hour → will OOM in 2 hours"
- "Disk usage at 90% → log rotation needed urgently"
- "CPU utilization trending up → scale out or optimize code"

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: Alert before resource exhaustion (5-10 minutes early)

---

#### 2A.4: Dependency Health Detection

**Problem**: Downstream service is broken, causing cascading failures

**What we'll add**:
- Service mesh integration (Istio)
- Cross-service latency correlation
- Dependency health scoring
- Blast radius calculation

**Output**: Understand dependency failures
- "Auth service is slow → 20% of requests timeout across all services"
- "Payment API is returning 5xx → 15 services affected"
- "Database replica is down → read traffic failing"

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: Identify root service, predict impact blast radius

---

**Phase 2A Deliverable**: Agent can handle 4 major incident types (pod crashes + 3 new)

---

### Phase 2B: Multi-Cloud Support (10 weeks)

**Goal**: Run on GCP, AWS, Azure with single codebase

#### 2B.1: Cloud Abstraction Layer

**What we're doing**:
- Implement abstraction interfaces (designed in MVP)
- Replace GCP-specific calls with cloud-agnostic ones

**Components to port**:
```
Logger        → GCP Logging    → CloudWatch (AWS)    → Azure Monitor
Metrics       → Cloud Monitoring → CloudWatch Metrics → Azure Monitor (Metrics)
StateStore    → Firestore      → DynamoDB (AWS)     → Cosmos DB (Azure)
LLM           → Vertex AI      → Bedrock (AWS)      → Azure OpenAI
TaskQueue     → Cloud Tasks    → SQS (AWS)          → Service Bus (Azure)
AlertBuffer   → Pub/Sub        → SNS/SQS (AWS)      → Service Bus (Azure)
```

**Effort**: 3 weeks  
**Team**: 2 Engineers (1 AWS, 1 Azure)  
**Success Criteria**: Abstraction layer allows toggling cloud providers with 1 config variable

---

#### 2B.2: AWS Support (EC2, ECS, EKS)

**What we'll add**:
- CloudWatch Logs + Metrics integration
- ECS task and EC2 crash detection
- IAM role assumption (instead of service account)
- CloudWatch Alarms as alert source

**Deployment**:
```
AWS Lambda (instead of Cloud Run)
DynamoDB (instead of Firestore)
SQS (instead of Cloud Tasks)
SNS (instead of Pub/Sub)
```

**Effort**: 3 weeks  
**Team**: 1 Engineer (AWS specialist)  
**Success Criteria**: Pod/task crash detection on ECS, same accuracy as GCP

---

#### 2B.3: Azure Support (AKS, App Service)

**What we'll add**:
- Azure Monitor Logs + Metrics
- AKS pod crash detection
- Managed Identity (instead of service account)
- Azure Event Grid as alert source

**Deployment**:
```
Azure Container Instances (instead of Cloud Run)
Cosmos DB (instead of Firestore)
Service Bus Queues (instead of Cloud Tasks)
Service Bus Topics (instead of Pub/Sub)
```

**Effort**: 3 weeks  
**Team**: 1 Engineer (Azure specialist)  
**Success Criteria**: Pod crash detection on AKS, same accuracy as GCP

---

#### 2B.4: Documentation & Multi-Cloud Demo

**What we'll create**:
- Deployment guides for each cloud
- Migration guides (GCP → AWS/Azure)
- Cost comparison calculator
- Multi-cloud example (same app on 3 clouds)

**Effort**: 1 week  
**Team**: 1 Engineer + 1 Technical Writer  
**Success Criteria**: Customers can deploy on any cloud in <2 hours

---

**Phase 2B Deliverable**: Agent runs on GCP, AWS, Azure with identical behavior

---

### Phase 2C: Semi-Autonomous Remediation (6 weeks)

**Goal**: Not just recommend fixes; **approve and execute safe remediations**

#### 2C.1: Approval Workflow for Safe Actions

**Safe actions** (pre-approved by human, can execute):
```
APPROVED_ACTIONS = [
  "increase_memory_limit",      # Pod OOMKill → increase by 25%, max 10GB
  "increase_cpu_limit",         # Pod CPU throttle → increase by 25%, max 4 cores
  "scale_out_replicas",         # Traffic spike → increase by 20%, max 100 replicas
  "enable_caching",             # Slow database queries → enable Redis (pre-configured)
  "trigger_log_rotation",       # Disk full → rotate logs immediately
  "restart_pod",                # Crash loop → restart (max 3x, then escalate)
]
```

**Forbidden actions** (human-only decision):
```
FORBIDDEN_ACTIONS = [
  "rollback_deployment",        # Could break data model
  "delete_data",                # Irreversible
  "change_database_config",     # Could cause downtime
  "redirect_traffic",           # Could load-balance incorrectly
]
```

**Workflow**:
```
Agent detects issue
  ↓
Agent recommends action
  ↓
Is action in APPROVED_ACTIONS? 
  ├─ YES: Execute + log + notify + get immediate feedback
  └─ NO: Create Jira ticket, wait for human approval
```

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: Execute 10+ remediation actions automatically with 100% safety

---

#### 2C.2: Remediation Tracking & Validation

**What we'll track**:
- Which remediation actions were executed
- Did they fix the incident? (yes/no/partial)
- How long to recovery?
- Any side effects?

**Example**:
```
Action: increase_memory_limit(payment-service, 2GB → 3GB)
Executed at: 2026-06-04T14:25:00Z
Result: Pod stable after 30 seconds
Metric: Memory usage drops from 2.1GB to 1.2GB
Feedback: Fixed! (engineer confirmed)
Confidence boost: 0.85 → 0.92
```

**Effort**: 1 week  
**Team**: 1 Engineer  
**Success Criteria**: Track 100% of executions, measure success rate >85%

---

#### 2C.3: Human Approval Gates for Risky Actions

**Semi-approved actions** (need human in the loop):
```
action = "scale_out_replicas"
if action.estimated_cost_increase > $100:
    # Need approval
    create_jira_approval_task()
    wait_for_human_decision()
    execute_only_if_approved()
```

**Effort**: 1 week  
**Team**: 1 Engineer  
**Success Criteria**: Jira tasks created and resolved <10 minutes

---

#### 2C.4: Rollback & Safety Guarantees

**If remediation makes things worse**:
- Automatic rollback within 5 minutes
- Log the incident
- Alert human immediately
- Escalate to "human-only" decision

**Example**:
```
Action: scale_out_replicas (10 → 20)
Result: Error rate increases 10x
Auto-detection: Rolled back to 10 replicas
Alert: "Scaling out made it worse. Human investigation needed."
```

**Effort**: 1 week  
**Team**: 1 Engineer  
**Success Criteria**: No cascading failures, <5 minute recovery

---

**Phase 2C Deliverable**: Agent can safely execute and roll back remediation actions

---

### Phase 2D: Customer Learning System (8 weeks)

**Goal**: **Agent learns from customer feedback** to improve future recommendations

#### 2D.1: Feedback Collection

**When incident is created**, ask engineer:
```
Was this diagnosis correct?
  ☑ Exactly right
  ☐ Close but not quite
  ☐ Completely wrong
  
Did the recommendation work?
  ☑ Yes, fixed it
  ☐ Partially fixed
  ☐ No, did something different
  
What did you actually do?
  [Open text]
  
Any secrets/PII exposed?
  ☐ Yes (we'll fix sanitizer)
```

**Effort**: 1 week  
**Team**: 1 Engineer  
**Success Criteria**: >50% feedback response rate

---

#### 2D.2: Feedback Analytics & Trend Detection

**Analyze feedback to find patterns**:
- "When we see error pattern X, customers always choose action Y"
- "Recommendation type Z has 65% approval rate (below our 80% target)"
- "This team types X in feedback 100% of the time → should pre-populate suggestion"

**Use this to**:
- Improve system prompts
- Change routing rules
- Pre-fill recommendations

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: Identify top 5 patterns, show >10% accuracy improvement

---

#### 2D.3: A/B Testing for Agent Improvements

**Test new prompts against old**:
```
Cohort A: Old system prompt (current production)
Cohort B: New system prompt (with improvements)

Measure:
- Recommendation approval rate
- Feedback sentiment
- Customer MTTR improvement
- False positive rate
```

**Effort**: 2 weeks  
**Team**: 1 Engineer (with DS support)  
**Success Criteria**: Roll out improvements with statistically significant gains (p < 0.05)

---

#### 2D.4: Feedback Loop UI in Jira

**Embedded in every Jira ticket**:
```
┌─────────────────────────────────────┐
│ How helpful was this analysis?      │
│ [👎] [👍] [❤️]                     │
│                                     │
│ [Optional] What would you change?   │
│ [__________________________] [Send]  │
└─────────────────────────────────────┘
```

**One-click feedback** → directly improves agent

**Effort**: 1 week  
**Team**: 1 Engineer (frontend + backend)  
**Success Criteria**: Easy feedback loop, >70% engagement

---

**Phase 2D Deliverable**: Agent learns and improves from customer feedback

---

### Phase 2E: Advanced Diagnostics - RAG for Code Search (6 weeks)

**Goal**: **Find relevant code semantically**, not by filename guessing

#### 2E.1: Code Embedding & Indexing

**What we'll do**:
- Index entire codebase using embeddings (Vertex AI Embeddings)
- Store in vector database (Weaviate or Pinecone)
- Update index on each deployment

**Example**:
```
Function: allocate_memory()
Embedding: [0.234, 0.156, -0.089, ...]

Later, agent searches:
Query: "memory allocation failure"
Embedding: [0.241, 0.162, -0.087, ...]
Similarity: 0.94 (match!)

Return: allocate_memory() source code
```

**Effort**: 2 weeks  
**Team**: 1 Engineer (ML/embeddings experience)  
**Success Criteria**: Index builds in <5 minutes, searches return relevant code

---

#### 2E.2: Semantic Code Search

**Agent can now search by meaning**:
```
Agent: "Find code that does memory allocation"
Search: Embedded query in vector space
Result: Top 5 matching functions
Return: allocate_memory(), pool_alloc(), malloc_wrapper(), ...
```

**vs old way**:
```
Agent: "Guess a file named allocator.rs"
Risk: Fetches wrong file, bloats context, misses real code
```

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: Semantic search finds correct code 90% of the time

---

#### 2E.3: Adaptive Context Window Management

**Use embeddings to intelligently choose context**:
```
Available token budget: 4000 tokens

Prioritize by relevance:
1. Most relevant code snippet (800 tokens) ✅
2. Stack trace (200 tokens) ✅
3. Recent deployment diffs (500 tokens) ✅
4. Related functions (800 tokens) ✅
5. Tests for that function (900 tokens) ❌ (would exceed)

Total: 2300 tokens (room for more; add error context)
```

**Effort**: 2 weeks  
**Team**: 1 Engineer  
**Success Criteria**: Better diagnostics, RCA confidence +15%

---

**Phase 2E Deliverable**: Agent uses semantic search to find relevant code

---

## Phase 2 Timeline & Resource Plan

```
Q3 2026:
  Week 1-2:   2A.1 Latency detection
  Week 3-4:   2A.2 Error rate detection
  Week 5-6:   2A.3 Resource exhaustion
  Week 7-8:   2A.4 Dependency health
  
Q4 2026:
  Week 1-3:   2B.1 Abstraction layer
  Week 4-6:   2B.2 AWS support
  Week 7-9:   2B.3 Azure support
  Week 10:    2B.4 Documentation
  
Q1 2027:
  Week 1-2:   2C.1 Approval workflows
  Week 3:     2C.2 Remediation tracking
  Week 4:     2C.3 Human approval gates
  Week 5:     2C.4 Rollback safety
  Week 6-7:   2D.1-2D.4 Learning system
  Week 8-9:   2E.1-2E.3 RAG for code
  Week 10:    Testing & documentation
```

**Team Size**: 5 Engineers (1 lead + 4 IC) + 1 Technical Writer

**Milestones**:
- [ ] End of Phase 2A: Multi-incident platform (Sept 2026)
- [ ] End of Phase 2B: Multi-cloud platform (Dec 2026)
- [ ] End of Phase 2C: Semi-autonomous platform (Jan 2027)
- [ ] End of Phase 2D: Learning platform (Jan 2027)
- [ ] End of Phase 2E: Advanced diagnostics (Jan 2027)

---

## Success Criteria for Phase 2

### Multi-Incident Success Criteria
- [ ] Handle 4+ incident types with same accuracy as MVP (>85%)
- [ ] MTTR further reduced by 30% (now 50%+ total)
- [ ] Cover 80% of real-world incidents (vs 40% for MVP)

### Multi-Cloud Success Criteria
- [ ] Identical behavior on GCP, AWS, Azure
- [ ] <2 hour deployment on any cloud
- [ ] Zero cloud-specific bugs
- [ ] Cost parity (±10%) across clouds

### Remediation Success Criteria
- [ ] Execute 10+ auto-remediation actions safely
- [ ] >85% effectiveness rate (fixes the incident)
- [ ] Zero catastrophic failures (rollback in <5min)
- [ ] <10 minute approval loop for human-gated actions

### Learning System Success Criteria
- [ ] Feedback response rate >50%
- [ ] Identify and implement 5+ improvements per quarter
- [ ] RCA accuracy improves from 85% → 92%
- [ ] Recommendation approval rate >80%

### RAG Success Criteria
- [ ] Semantic search finds correct code 90% of the time
- [ ] RCA confidence increases by 15%
- [ ] Zero hallucinated file paths (vs current mitigations)

---

## Investment & ROI

### Phase 2 Investment
- 5 Engineers × 12 weeks
- 1 ML engineer (embeddings)
- 1 Technical writer
- Cloud infrastructure, embeddings API, vector DB

**Estimated Cost**: $500K - $750K

### Phase 2 ROI
**Customer Impact**:
- MTTR reduced 75% (MVP 50%, Phase 2 adds 25%)
- Handles 80% of incidents (vs 40%)
- Semi-autonomous fixes reduce human time further
- Learning system compounds improvements over time

**Business Impact**:
- Expand customer base (multi-cloud requirement)
- Increase pricing (more features, more incident types)
- Reduce support burden (autonomous remediation)
- Competitive advantage (no other SRE agent on market)

**ROI**: 4-6x within 18 months

---

## Dependencies & Risks

### External Dependencies
- [ ] LLM provider stability (Claude/Gemini)
- [ ] Customer willingness to approve autonomous remediation
- [ ] Multi-cloud availability (AWS Bedrock vs Vertex AI)

### Internal Dependencies
- [ ] MVP customer feedback (informs Phase 2 direction)
- [ ] Team hiring (need 3 specialized engineers)
- [ ] Product roadmap alignment (other product initiatives)

### Risks
- [ ] Semantic code search may not improve diagnostics
- [ ] Semi-autonomous fixes may cause cascading failures
- [ ] Multi-cloud adds complexity; bugs harder to find
- [ ] Learning system requires high feedback quality

**Mitigation**:
- A/B test before full rollout
- Extensive testing on safe actions first
- Dedicated multi-cloud testing team
- Reward feedback quality (public leaderboard?)

---

## Decision Gates (Kill Criteria)

**Before starting Phase 2A (multi-incident types)**:
- [ ] MVP customer MTTR reduction >40%
- [ ] Platform uptime >99.5%
- [ ] Customer satisfaction >8/10

**Before starting Phase 2B (multi-cloud)**:
- [ ] 5+ customers on Phase 2A
- [ ] Incident type accuracy >85%
- [ ] Engineering team stable & confident

**Before starting Phase 2C (auto-remediation)**:
- [ ] Zero catastrophic failures in Phase 2B testing
- [ ] Customer approval for autonomous actions
- [ ] Safety review completed & approved

**Before starting Phase 2E (RAG)**:
- [ ] RCA accuracy plateau at 85%
- [ ] Semantic search shows 15%+ improvement in testing
- [ ] Vector DB performance validated

---

## Customer Feedback Loop

**Continuously ask customers**:
- Which incident types cause the most pain?
- Which cloud platforms are you on?
- Would you approve autonomous remediation? (with safeguards)
- What features would improve your life most?

**Quarterly roadmap updates** based on feedback

---

## Communication Plan

**Internal**:
- Bi-weekly Phase 2 planning meetings
- Weekly status updates to leadership
- Monthly engineering deep-dives

**External**:
- Quarterly customer roadmap reviews
- Monthly "what's coming" posts
- Beta access to Phase 2A features (Q3 2026)

---

## Conclusion

Phase 2 transforms Agentic SRE from "cool MVP" to "mission-critical platform."

**By end of Phase 2**:
- ✅ Multi-incident platform (covers 80% of real incidents)
- ✅ Multi-cloud platform (GCP, AWS, Azure)
- ✅ Semi-autonomous fixes (human-approved)
- ✅ Learning system (improves over time)
- ✅ Advanced diagnostics (semantic code search)

**Success measure**: Customers reduce incident response time by 75%+ and incident count by 40%+ through autonomous triage and safe remediation.

---

**Next**: Collect MVP feedback (Q2 2026), finalize Phase 2 roadmap (Q3 2026), begin Phase 2A (Sept 2026)

