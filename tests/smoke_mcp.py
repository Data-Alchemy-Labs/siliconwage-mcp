#!/usr/bin/env python3
"""Real-client smoke test for the Silicon Wage MCP server."""
import asyncio
import json
import os

from mcp.client.session import ClientSession
from mcp.client.streamable_http import streamable_http_client

URL = os.environ.get("MCP_URL", "http://127.0.0.1:8091/mcp")
JOB = os.environ.get("MCP_TEST_JOB", "P81517130")
WALLET = os.environ.get("MCP_TEST_WALLET", "0x1111111111111111111111111111111111111111")
WRITES = os.environ.get("MCP_TEST_WRITES") == "1"


async def main():
    async with streamable_http_client(URL) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            assert init.server_info.name == "Silicon Wage"
            tools = await session.list_tools()
            names = sorted(t.name for t in tools.tools)
            assert names == ["claim_job", "get_job", "list_jobs", "payout_status", "submission_status", "submit_work"], names
            print("tools", names)

            jobs = await session.call_tool("list_jobs", {})
            assert not jobs.is_error
            data = json.loads(jobs.content[0].text)
            assert isinstance(data.get("jobs"), list)
            print("list_jobs", len(data["jobs"]))

            job = await session.call_tool("get_job", {"job_id": JOB})
            assert not job.is_error
            spec = json.loads(job.content[0].text)
            assert spec.get("id") == JOB
            print("get_job", spec.get("title"))

            status = await session.call_tool("submission_status", {"job_id": JOB, "wallet": WALLET})
            assert not status.is_error
            print("submission_status", len(json.loads(status.content[0].text).get("submissions", [])))

            payout = await session.call_tool("payout_status", {"payout_id": 8})
            assert not payout.is_error
            print("payout_status", json.loads(payout.content[0].text).get("status"))

            if WRITES:
                claim = await session.call_tool("claim_job", {"job_id": JOB, "wallet": WALLET, "items": ["R01"]})
                assert not claim.is_error
                print("claim_job", json.loads(claim.content[0].text).get("working"))
                sub = await session.call_tool("submit_work", {
                    "job_id": JOB, "wallet": WALLET,
                    "payload": {"items": [{"item_id": "R01", "outcome_id": "IDENTIFIED",
                                           "answer": {"lei": "00000000000000000098"},
                                           "evidence": {"url": "https://example.com"}}]},
                })
                assert not sub.is_error
                print("submit_work", json.loads(sub.content[0].text))
    print("MCP SMOKE PASS")


if __name__ == "__main__":
    asyncio.run(main())
