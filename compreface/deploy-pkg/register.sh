#!/bin/bash
set -e
curl -s -w '\nHTTP=%{http_code}\n' -X POST http://127.0.0.1:8051/admin/user/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"sp3-ops@mediation.local","firstName":"SP3","lastName":"Ops","password":"Sp3-Face-2026-Verify"}'
