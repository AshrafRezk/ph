# Salesforce Meetings API — Contract for Mendix

**Version:** 1.0  
**Org:** Zeta Pharma (`https://zetapharma.my.salesforce.com`)  
**Status:** GET meetings / expenses / attachments — **ready**  
**Auth:** OAuth 2.0 Client Credentials via External Client App **Mendix Integration API** (Meetings + Time Off)

---

## 1. Authentication

### 1.1 Flow

Use **OAuth 2.0 Client Credentials** (server-to-server). No interactive login.

```http
POST https://zetapharma.my.salesforce.com/services/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id={CONSUMER_KEY}
&client_secret={CONSUMER_SECRET}
```

**Success (200):**

```json
{
  "access_token": "00D...!",
  "signature": "...",
  "scope": "...",
  "instance_url": "https://zetapharma.my.salesforce.com",
  "id": "https://login.salesforce.com/id/00D.../005...",
  "token_type": "Bearer",
  "issued_at": "..."
}
```

Use on every API call:

```http
Authorization: Bearer {access_token}
```

### 1.2 Integration identity (Salesforce side — already created)

| Item | Value |
|------|--------|
| External Client App | `Mendix Integration API` (`Mendix_Meetings_API`) |
| Run-as user | `mendix.api@zetapharma.com` |
| Profile | Salesforce API Only System Integrations |
| Permission sets | `Meeting_Mendix_API`, `Meeting_User` |
| Consumer Key | See `AUTH_CREDENTIALS.local.md` (private) |

**Consumer Secret** cannot be read via API after creation. Salesforce admin reveals it once from:

**Setup → External Client App Manager → Mendix Integration API → Settings → OAuth Settings → Consumer Key and Secret → Reveal**

Share Consumer Key + Secret with Mendix over a secure channel (not email if possible).

### 1.3 Smoke test checklist

- [ ] Token request returns `access_token`
- [ ] `GET /meetings/v1?limit=5` returns 200
- [ ] `GET /meetings/v1/MTG-DEMO-SPEAKER?includeContent=true` returns expenses + `contentBase64`
- [ ] Decode base64 → valid PDF

---

## 2. Base URL

```
https://zetapharma.my.salesforce.com/services/apexrest
```

All paths below are relative to that base.

---

## 3. Endpoints (available now)

### 3.1 List meetings

```http
GET /meetings/v1
```

| Query | Type | Description |
|-------|------|-------------|
| `status` | string | Exact status, e.g. `Approved` |
| `recordType` | string | Developer name, e.g. `Speaker_Meeting` |
| `updatedSince` | ISO datetime | Filter by `LastModifiedDate` |
| `limit` | int | 1–200 (default 50) |
| `offset` | int | Pagination offset |

**Response 200:**

```json
{
  "totalSize": 1,
  "records": [
    {
      "id": "a1P...",
      "meetingId": "MTG-DEMO-SPEAKER",
      "uniqueIntegrationId": "MX-DEMO-Speaker_Meeting",
      "name": "MTG-00012",
      "recordType": "Speaker_Meeting",
      "recordTypeLabel": "Speaker Meeting",
      "status": "Approved",
      "startDateTime": "2026-09-15T06:00:00.000Z",
      "endDateTime": "2026-09-15T09:00:00.000Z",
      "deliveryFormat": "Out-of-office",
      "totalEstimatedExpenses": 8500.0,
      "totalActualExpenses": 9200.0
    }
  ]
}
```

### 3.2 Get meeting detail

```http
GET /meetings/v1/{key}
GET /meetings/v1/{key}?includeContent=true
```

`{key}` may be:

- Salesforce Id  
- `meetingId` (e.g. `MTG-DEMO-SPEAKER`)  
- `uniqueIntegrationId` (e.g. `MX-DEMO-Speaker_Meeting`)

**`includeContent=true`** adds `contentBase64` on each attachment so Mendix can persist the file without a second call.

**Response 200 (shape):**

```json
{
  "id": "a1P...",
  "meetingId": "MTG-DEMO-SPEAKER",
  "uniqueIntegrationId": "MX-DEMO-Speaker_Meeting",
  "name": "MTG-00012",
  "recordType": "Speaker_Meeting",
  "recordTypeLabel": "Speaker Meeting",
  "status": "Approved",
  "startDateTime": "2026-09-15T06:00:00.000Z",
  "endDateTime": "2026-09-15T09:00:00.000Z",
  "deliveryFormat": "Out-of-office",
  "totalEstimatedExpenses": 8500.0,
  "totalActualExpenses": 9200.0,
  "expenses": [
    {
      "id": "a1A...",
      "name": "ME-00001",
      "recordType": "Actual",
      "type": "Meal",
      "amount": 9200.0,
      "currencyCode": "EGP",
      "status": "Approved",
      "integrationStatus": "Ready",
      "externalExpenseReportId": null,
      "dateTime": "2026-09-15T06:00:00.000Z",
      "comments": "Venue catering invoice",
      "attachmentIds": ["069..."]
    }
  ],
  "attachments": [
    {
      "contentDocumentId": "069...",
      "contentVersionId": "068...",
      "fileName": "eta-invoice-744J0JNJYYQDS2KNVFPTAZVK10.pdf",
      "contentType": "application/pdf",
      "size": 60856,
      "linkedTo": "Expense",
      "linkedRecordId": "a1A...",
      "downloadUrl": "/services/apexrest/meetings/v1/MTG-DEMO-SPEAKER/attachments/069...",
      "contentBase64": "JVBERi0xLjQK...(only if includeContent=true)"
    }
  ]
}
```

### 3.3 Download attachment (raw bytes)

```http
GET /meetings/v1/{key}/attachments/{contentDocumentId}
```

- Body = binary file  
- `Content-Type` = e.g. `application/pdf`  
- Prefer `includeContent=true` on detail for sync jobs that write to Mendix DB

---

## 4. Errors

```json
{ "message": "human readable error" }
```

| HTTP | Meaning |
|------|---------|
| 200 | Success |
| 400 | Bad request / unsupported path |
| 401 / 403 | Auth / permission |
| 404 | Meeting or attachment not found |
| 500 | Server error |

---

## 5. Demo data (ready in org)

| meetingId | uniqueIntegrationId | Status |
|-----------|---------------------|--------|
| `MTG-DEMO-SPEAKER` | `MX-DEMO-Speaker_Meeting` | Approved |
| `MTG-DEMO-REGIONAL` | `MX-DEMO-Regional_Standalone` | Pending GPM Approval |
| `MTG-DEMO-NATIONAL` | `MX-DEMO-National_Standalone` | Draft |
| `MTG-DEMO-ADBOARD` | `MX-DEMO-Advisory_Board` | Closed |
| `MTG-DEMO-RTD` | `MX-DEMO-RTD` | Pending NLM Approval |
| `MTG-DEMO-AV` | `MX-DEMO-AV_Action` | Approved |
| `MTG-DEMO-PROMO` | `MX-DEMO-Promotional_Activity` | Concluded |

Most include expenses + sample invoice PDF.

---

## 6. Mendix mapping tips

| Salesforce field | Suggested Mendix use |
|------------------|----------------------|
| `meetingId` / `uniqueIntegrationId` | External keys (idempotent sync) |
| `status` | Workflow / status |
| `expenses[]` | Expense lines |
| `attachments[].contentDocumentId` | File external id |
| `attachments[].contentBase64` | Store System.Image / FileDocument |
| `attachments[].fileName` / `contentType` | File metadata |

**Recommended sync:** poll `GET /meetings/v1?updatedSince=...` then detail with `includeContent=true` for changed ids.

---

## 7. Out of scope for v1.0 (next)

Same External Client App (**Mendix Integration API**) will authenticate these as well:

- `POST` / `PUT` create-update meetings + expenses + invoice upload  
- Time Off (TOT) Mendix API  

Import `Mendix_Meetings_API.postman_collection.json` to exercise Meetings v1.0 end-to-end.
