# Oct 22 monthly pack — load status

Source: `Zeta Provided Data/22Oct-20261024T181847Z-1-001.zip`  
Card: Admin Console → **Monthly data pack** (deploy `0Afiv0000005aqrCAA`)

| Dataset | Status | Notes |
|--------|--------|--------|
| Sept leave | Loaded | 1154 TOR (`PACK-L-`); some fails in SDIB-00013 |
| Sept TOT | Loaded | 2368 TOR (`PACK-T-`); some fails in SDIB-00014 |
| May–Sept visits | Sample only | 40 `PACKV-` MAY visits; drop zip on card for full load |
| EPDA / POS / IBNSINA sales | Not complete | CLI hit CPU / alias match fails — use card; rematch IBNSINA in Distributors Management |

## Follow-ups already kicked off
- `PharmacySalesProductBackfillBatch` job `707iv000004ygOrAAI` (Product__c on existing sales lines)

## Manual next
1. Admin Console → Monthly data pack → drop Oct 22 zip → import remaining sales + full visits  
2. Distributors Management → **Re-match unmapped** (IBNSINA, 200/click)
