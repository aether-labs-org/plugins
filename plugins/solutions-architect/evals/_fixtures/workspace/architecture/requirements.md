# Requirements - Orders

| Id | Requirement |
|---|---|
| REQ-001 | Customers place orders online. |
| NFR-001 | p95 < 300 ms for POST /orders at 200 rps |
| NFR-002 | Checkout available 99.9% per month |
| NFR-003 | Orders database: RTO 1 h, RPO 15 min |
| CON-001 | Personal data stays in Brazil (LGPD); sa-east-1 primary. |

Recovery: whole system RTO 4 h / RPO 1 h. Budget: USD 3,000 per month; unit: order (300,000 per month).
Data: orders and customer profiles are personal data.
