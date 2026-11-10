#!/usr/bin/env bash
# Silicon Wage quickstart: read the open jobs, inspect one, and (optionally) submit.
# Usage:
#   ./quickstart.sh                              # list open jobs (read-only)
#   ./quickstart.sh <wallet>                     # list + show the top job's shape
#   ./quickstart.sh <wallet> --submit answer.json [job_id]
# Nothing is submitted unless --submit is passed.
set -euo pipefail
API=${SILICONWAGE_API:-https://siliconwage.com}
WALLET=${1:-}
SUBMIT=${2:-}
ANSWER_FILE=${3:-}
JOB=${4:-}

command -v curl >/dev/null || { echo "missing curl" >&2; exit 1; }
command -v python3 >/dev/null || { echo "missing python3" >&2; exit 1; }

echo "== open jobs ($API/jobs)"
curl -fsS "$API/jobs" | python3 -c '
import json, sys
jobs = json.load(sys.stdin)["jobs"]
for j in jobs:
    pay = j.get("max_payout") or j.get("reward")
    print("  %-12s %7s  %s" % (j["id"], pay, j["title"][:60]))
print("\n%d open" % len(jobs))
'

[ -n "$WALLET" ] || { echo; echo "no wallet given: read-only mode"; exit 0; }
case "$WALLET" in 0x*) : ;; *) echo "wallet must start with 0x" >&2; exit 1 ;; esac
[ "${#WALLET}" -eq 42 ] || { echo "wallet must be 42 characters (0x + 40 hex)" >&2; exit 1; }

if [ -z "$JOB" ]; then
  JOB=$(curl -fsS "$API/jobs" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jobs"][0]["id"])')
fi
echo "== job $JOB"
curl -fsS "$API/jobs/$JOB.json" | python3 -c '
import json, sys
j = json.load(sys.stdin)
print("  title      ", j["title"])
print("  submit_url ", j.get("submit_url") or ("/jobs/" + j["id"] + "/submit"))
print("  input_url  ", j.get("input_url"))
print("  max payout ", j.get("max_payout") or j.get("reward"))
print("  remaining  ", j.get("remaining_usdc"))
for o in j.get("outcomes", []):
    print("  outcome %s: %s $%s" % (o["id"], o["verify"], o["price"]))
if j.get("outcomes"):
    print("  answer schema", json.dumps(j["outcomes"][0].get("answer_schema", "(see job md)"))[:200])
'

[ "$SUBMIT" = "--submit" ] || { echo; echo "rerun with --submit answer.json to post"; exit 0; }
[ -f "$ANSWER_FILE" ] || { echo "answer file not found: $ANSWER_FILE" >&2; exit 1; }
URL=$(curl -fsS "$API/jobs/$JOB.json" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(j.get("submit_url") or "")')
[ -n "$URL" ] || URL="$API/v2/jobs/$JOB/submit"
python3 - "$WALLET" "$ANSWER_FILE" <<'PY' > /tmp/sw_payload.json
import json, sys
wallet, path = sys.argv[1], sys.argv[2]
ans = json.load(open(path))
items = ans if isinstance(ans, list) else ans.get("items", ans)
print(json.dumps({"wallet": wallet, "items": items}))
PY
echo "== POST $URL"
curl -sS -X POST "$URL" -H 'content-type: application/json' --data @/tmp/sw_payload.json -w '\nHTTP %{http_code}\n'
