# GitHub App Setup Guide for Agentic SRE Platform v1.0

**Purpose**: Enable Agentic SRE to safely fetch source code and recent commits for incident analysis

**Security Principle**: Minimal required permissions only (read-only, specific repos)

**Time Required**: 10-15 minutes

---

## Before You Start

**You'll need**:
- [ ] GitHub organization admin access (or someone with app installation permissions)
- [ ] A list of repositories you want Agentic SRE to access
  - Example: `payment-service`, `auth-service`, `order-service`
  - ⚠️ DO NOT grant access to your entire organization (supply chain risk)

**You'll get**:
- [ ] App ID (12 digits)
- [ ] Installation ID (12 digits)
- [ ] Private Key (RSA key, keep secure!)

---

## Step 1: Create GitHub App

### 1.1 Navigate to GitHub Apps

**For your organization**:
1. Go to: `https://github.com/organizations/[YOUR-ORG]/settings/apps`
   - Replace `[YOUR-ORG]` with your organization name
   - Example: `https://github.com/organizations/acme-corp/settings/apps`

2. Click **"New GitHub App"** (top right)

### 1.2 Fill in App Details

**Application name**:
```
Agentic SRE
```

**Homepage URL**:
```
https://agentic-sre.platform.com
```

**Description** (optional):
```
Autonomous incident analysis and root cause diagnostics
```

**Webhook URL** (optional for MVP, leave blank):
```
(Leave blank - we don't need webhooks yet)
```

**Webhook active**: 
```
☐ (Uncheck - not needed for MVP)
```

### 1.3 Set Permissions (CRITICAL)

**Read these carefully. Only select what's needed.**

**Repository permissions** (what the app can do to your repos):
- [ ] **Contents**: `Read-only` ✅ (We need this to fetch source code)
- [ ] **Metadata**: `Read-only` ✅ (Required by GitHub, harmless)
- All others: Leave as `No access` (default)

**Organization permissions** (access to org-level stuff):
- Leave all as `No access` (default)

**User permissions** (access to user data):
- Leave all as `No access` (default)

### 1.4 Save the App

1. Scroll to bottom
2. Click **"Create GitHub App"**
3. GitHub will show you the confirmation page with:
   - App ID (save this!)
   - Private Key button (we'll use this next)

---

## Step 2: Generate & Secure Private Key

### 2.1 Generate Private Key

1. On the GitHub App settings page, scroll down to **"Private keys"** section
2. Click **"Generate a private key"**
3. GitHub generates a `.pem` file and **downloads it automatically**

⚠️ **CRITICAL**: 
- This is the ONLY time you can download the key
- If you lose it, you'll have to regenerate
- **NEVER commit this to Git**
- **NEVER share this publicly**

### 2.2 Secure the Private Key

1. Open the downloaded file: `agentic-sre.2024.private-key.pem`
2. Copy the contents (the whole key, including `-----BEGIN RSA PRIVATE KEY-----`)
3. **DO NOT store in Git**
4. **Store securely** (password manager or secure document storage)
5. You'll give this to the Agentic SRE team via secure channel (encrypted email, secure document, etc.)

---

## Step 3: Install App to Repositories

### 3.1 Navigate to Install Page

1. Go back to your GitHub App settings page
2. Look for **"Install App"** in the left sidebar
3. Click on **"Install App"**

### 3.2 Select Repositories

1. GitHub shows: "Select repositories..."
2. Choose **"Only select repositories"** (important!)
3. Check the boxes for repos you want Agentic SRE to analyze:

**Recommended**:
```
☑ payment-service
☑ auth-service
☑ order-service
```

**NOT recommended** (too broad):
```
☐ All repositories (this is a supply chain risk)
☐ Private fork repositories (unnecessary)
```

4. Click **"Install"**

GitHub will show a confirmation: "Installation successful!"

---

## Step 4: Get Installation ID

### 4.1 Find Installation ID

1. Go back to your GitHub App settings: `https://github.com/organizations/[ORG]/settings/apps/agentic-sre`
2. Look for **"Recent deliveries"** or **"Installations"** section
3. Click on your installation
4. The URL will show the Installation ID:
   ```
   https://github.com/apps/agentic-sre/installations/[INSTALLATION-ID]
   ```

**Example**:
```
https://github.com/apps/agentic-sre/installations/67890
↑ Installation ID = 67890
```

---

## Step 5: Share Credentials with Agentic SRE Team

### 5.1 Gather Your Credentials

You should now have:

```
App ID: 123456
Installation ID: 67890
Private Key: -----BEGIN RSA PRIVATE KEY-----
              MIIEvQIBADANBgkqhkiG9w0BAQE...
              [... many lines ...]
              -----END RSA PRIVATE KEY-----

Allowed Repos: payment-service, auth-service, order-service
```

### 5.2 Send to Agentic SRE Team

**Via secure channel** (not Slack, not unencrypted email):
- [ ] Send an encrypted email
- [ ] Or paste into a secure document (Google Drive with password)
- [ ] Or share via your secure credential manager

**Include**:
```
Organization: acme-corp
GitHub App ID: 123456
Installation ID: 67890
Private Key: [full key]
Allowed Repos: payment-service, auth-service, order-service
```

---

## Verification: Test the App

### 6.1 Ask Agentic SRE Team to Verify

Once the team receives your credentials, they'll test:

```bash
# Pseudo-test command (team runs this)
curl -X GET https://api.github.com/app/installations/[INSTALLATION-ID]/repositories \
  -H "Authorization: Bearer [JWT_TOKEN]" \
  -H "Accept: application/vnd.github+json"

# If successful: Shows list of installed repos
# If failed: Shows error (auth or permission issue)
```

---

## Troubleshooting

### Problem: "404 Not Found" when accessing GitHub App settings

**Cause**: Wrong organization name or you don't have admin access

**Fix**:
1. Verify you're in the right organization
2. Check you have "Owner" or "Admin" role
3. Go to: `https://github.com/settings/organizations`
4. Select your organization
5. Go to Settings → Developer settings → GitHub Apps

---

### Problem: Can't find "New GitHub App" button

**Cause**: You're not in the organization; you're in your personal settings

**Fix**:
1. Go to: `https://github.com/organizations/[YOUR-ORG]/settings/apps`
2. NOT: `https://github.com/settings/apps`
3. The URL must have `/organizations/` in it

---

### Problem: Private Key disappeared after I closed the browser

**Cause**: GitHub only shows the key ONCE. You lost it.

**Fix** (regenerate):
1. Go back to GitHub App settings
2. Scroll to "Private keys"
3. Click "Delete" on the old key
4. Click "Generate a private key" (new key)
5. Download and save immediately

---

### Problem: Agentic SRE says "403 Forbidden - Insufficient permissions"

**Cause**: GitHub App doesn't have `Contents: Read-only` permission

**Fix**:
1. Go to GitHub App settings
2. Look for "Permissions" section
3. Verify **"Contents"** is set to **"Read-only"**
4. If not: Click "Edit", change to "Read-only", click "Save"

---

### Problem: Agentic SRE says "404 Not Found" for repository

**Cause**: GitHub App not installed on that repository

**Fix**:
1. Go to GitHub App settings
2. Click "Install App"
3. Verify the repository is checked
4. If not: Check the box and click "Install"

---

## Security Best Practices

### ✅ DO

- [ ] Grant only `Contents: Read-only` permission (not write)
- [ ] Install on specific repositories (not entire organization)
- [ ] Store private key securely (not in Git)
- [ ] Share private key via encrypted channel only
- [ ] Rotate private key every 6 months
- [ ] Use strong organization password
- [ ] Enable 2FA on your GitHub account

### ❌ DON'T

- [ ] Install GitHub App on entire organization
- [ ] Grant write or admin permissions
- [ ] Commit private key to Git
- [ ] Share private key in Slack or email (unencrypted)
- [ ] Reuse the same key for multiple apps
- [ ] Leave the private key lying around on your computer

---

## Rotating the Private Key (Every 6 Months)

**When to rotate**:
- Every 6 months as best practice
- Immediately if you think the key was compromised
- When leaving a team member (revoke their access)

**Steps**:
1. Generate a new private key (see Step 2)
2. Send new key to Agentic SRE team (see Step 5)
3. Team updates Firestore credentials
4. Team tests with new key
5. Delete old private key in GitHub

---

## Revoking Access (Emergency)

**If you need to immediately revoke access**:

1. Go to GitHub App settings
2. Click "Install App"
3. Find your installation
4. Click "Uninstall"
5. Confirm

**Agentic SRE can no longer**:
- Fetch source code
- See commit history
- Access your repositories

(This is OK - the platform can still work, just without code context)

---

## FAQ

### Q: Why does Agentic SRE need source code access?

**A**: When a pod crashes, we fetch recent code changes to correlate with the crash time. Example:
- Pod started crashing at 14:18
- Commit abc123 deployed at 14:15
- Likely cause: Memory leak in abc123
- Recommendation: Rollback to previous version

Without source code access, we can't make this connection.

### Q: Is it safe to give Agentic SRE access to our source code?

**A**: Yes, because:
1. The GitHub App has `Read-only` permission (can't modify code)
2. The app can only access repos you explicitly approve
3. The private key is stored encrypted
4. All access is logged in GitHub
5. You can revoke access instantly

### Q: What if we change repositories later?

**A**: 
1. Go to GitHub App settings
2. Click "Install App"
3. Check/uncheck repositories
4. Save
5. Changes take effect immediately

### Q: What if we need to add more repositories?

**A**: Same process as above. You can update the list anytime.

### Q: What happens if we revoke the GitHub App?

**A**: Agentic SRE can't fetch source code anymore, but the platform still works. Incidents will be created without code context (lower quality RCAs).

### Q: How do we know if the GitHub App is working?

**A**: Check your Jira tickets:
- If they mention specific file names and code snippets → Working
- If they're missing code context → Not working (likely auth issue)

---

## Next Steps

1. ✅ Created GitHub App (Step 1)
2. ✅ Generated private key (Step 2)
3. ✅ Installed on repositories (Step 3)
4. ✅ Found Installation ID (Step 4)
5. ✅ Sent credentials to Agentic SRE team (Step 5)
6. ⏳ Wait for team to verify and confirm working (Step 6)
7. 📊 Start seeing better incident analysis in Jira tickets

---

## Support

**Questions?**
- Email: support@agentic-sre.platform.com
- Slack: #agentic-sre-support
- GitHub issue: [Link to repo]

**Need to revoke?**
- Uninstall the app (Step 3)
- Agentic SRE will work without source code context

**Technical help**:
- GitHub docs: https://docs.github.com/en/apps
- Agentic SRE docs: https://docs.agentic-sre.platform.com

---

**You're all set!** Your Agentic SRE platform now has secure source code access. 🎉

