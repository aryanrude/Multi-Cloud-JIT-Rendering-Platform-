#!/usr/bin/env python3
"""
Seed the compatibility matrix table and smoke test both API endpoints.

Usage:
    python scripts/seed_and_test.py

Reads endpoint URLs from terraform output automatically.
Requires: boto3, requests  (pip install boto3 requests)
"""

import json
import subprocess
import sys
import boto3
import requests

# ── Read Terraform outputs ────────────────────────────────────────────────────

def get_tf_outputs():
    result = subprocess.run(
        ["terraform", "output", "-json"],
        capture_output=True, text=True, cwd="terraform"
    )
    if result.returncode != 0:
        print("ERROR: Could not read terraform outputs. Did you run `terraform apply`?")
        print(result.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


# ── Seed compatibility matrix ─────────────────────────────────────────────────

VALID_COMBINATIONS = [
    {"combo_id": "blender-3.6-cycles-3.6",     "gpu_required": True,  "min_vram_gb": 8},
    {"combo_id": "blender-4.0-cycles-4.0",     "gpu_required": True,  "min_vram_gb": 12},
    {"combo_id": "blender-4.0-eevee-4.0",      "gpu_required": True,  "min_vram_gb": 8},
    {"combo_id": "houdini-20.0-mantra-20.0",   "gpu_required": False, "min_vram_gb": 0},
    {"combo_id": "houdini-20.0-redshift-3.5",  "gpu_required": True,  "min_vram_gb": 16},
    {"combo_id": "maya-2024-arnold-7.0",       "gpu_required": True,  "min_vram_gb": 8},
    {"combo_id": "maya-2024-vray-6.0",         "gpu_required": True,  "min_vram_gb": 8},
]


def seed_table(table_name: str, region: str = "us-east-1"):
    dynamodb = boto3.resource("dynamodb", region_name=region)
    table = dynamodb.Table(table_name)

    print(f"\nSeeding {len(VALID_COMBINATIONS)} combinations into {table_name}...")

    with table.batch_writer() as batch:
        for item in VALID_COMBINATIONS:
            batch.put_item(Item=item)

    print("Seed complete.")


# ── Smoke tests ───────────────────────────────────────────────────────────────

def test_provision(endpoint: str):
    print(f"\n--- POST {endpoint} ---")

    # Valid request
    payload = {
        "software":       "blender",
        "version":        "4.0",
        "render_engine":  "cycles",
        "engine_version": "4.0",
        "machine_type":   "gpu-large",
        "count":          2,
    }
    resp = requests.post(endpoint, json=payload)
    print(f"[VALID]   {resp.status_code} → {resp.json()}")
    assert resp.status_code == 200, "Expected 200 for valid combo"
    request_id = resp.json()["request_id"]

    # Invalid combo
    bad_payload = {**payload, "render_engine": "nonexistent", "engine_version": "0.0"}
    resp = requests.post(endpoint, json=bad_payload)
    print(f"[INVALID] {resp.status_code} → {resp.json()}")
    assert resp.status_code == 400, "Expected 400 for invalid combo"

    # Missing fields
    resp = requests.post(endpoint, json={"software": "blender"})
    print(f"[MISSING] {resp.status_code} → {resp.json()}")
    assert resp.status_code == 400, "Expected 400 for missing fields"

    return request_id


def test_callback(endpoint: str, request_id: str):
    print(f"\n--- POST {endpoint} ---")

    # Simulate VM reporting ready
    payload = {
        "request_id":  request_id,
        "status":      "ready",
        "instance_id": "i-0abc123456789def0",
        "cloud":       "aws",
    }
    resp = requests.post(endpoint, json=payload)
    print(f"[READY]   {resp.status_code} → {resp.json()}")
    assert resp.status_code == 200

    # Duplicate callback — should be idempotent (already in terminal state)
    resp = requests.post(endpoint, json=payload)
    print(f"[DUPE]    {resp.status_code} → {resp.json()}")
    assert resp.status_code == 200

    # Missing request_id
    resp = requests.post(endpoint, json={"status": "ready"})
    print(f"[MISSING] {resp.status_code} → {resp.json()}")
    assert resp.status_code == 400


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    outputs = get_tf_outputs()

    table_name        = outputs["compatibility_matrix_table"]["value"]
    provision_url     = outputs["provision_endpoint"]["value"]
    callback_url      = outputs["callback_endpoint"]["value"]

    seed_table(table_name)
    request_id = test_provision(provision_url)
    test_callback(callback_url, request_id)

    print("\nAll tests passed.")
