#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.error
import urllib.request
from http.cookiejar import CookieJar


def call_json(opener, base_url, path, params=None):
    payload = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": params or {},
        "id": 1,
    }
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        base_url.rstrip("/") + path,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with opener.open(request, timeout=30) as response:
        body = json.loads(response.read().decode("utf-8"))
    if body.get("error"):
        raise RuntimeError(json.dumps(body["error"], indent=2, ensure_ascii=False))
    return body.get("result")


def main():
    parser = argparse.ArgumentParser(description="Probe the Odoo Native UI Bridge.")
    parser.add_argument("--url", default="http://127.0.0.1:8069")
    parser.add_argument("--db", required=True)
    parser.add_argument("--login", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--model", default="res.partner")
    args = parser.parse_args()

    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))

    try:
        health = call_json(opener, args.url, "/native-ui/health")
        auth = call_json(
            opener,
            args.url,
            "/web/session/authenticate",
            {
                "db": args.db,
                "login": args.login,
                "password": args.password,
            },
        )
        if not auth or not auth.get("uid"):
            raise RuntimeError("Authentication failed.")

        session = call_json(opener, args.url, "/native-ui/session")
        snapshot = call_json(opener, args.url, "/native-ui/snapshot/index")
        fields = call_json(
            opener,
            args.url,
            f"/native-ui/model/{args.model}/fields",
            {"attributes": ["string", "type", "required", "readonly", "relation"]},
        )
        records = call_json(
            opener,
            args.url,
            f"/native-ui/model/{args.model}/records",
            {"fields": ["display_name"], "limit": 5},
        )
    except (urllib.error.URLError, RuntimeError) as exc:
        print(f"Native UI probe failed: {exc}", file=sys.stderr)
        return 1

    print("Native UI Bridge OK")
    print(f"Odoo: {health['odoo_version']}")
    print(f"User: {session['user']['name']} ({session['database']})")
    print(f"Snapshot hash: {snapshot['manifest']['content_hash']}")
    print(f"Top-level apps: {len(snapshot['menus'].get('children', []))}")
    print(f"{args.model} fields: {fields['field_count']}")
    print(f"{args.model} sample rows: {records['count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
