# -*- coding: utf-8 -*-
import json
import sys

path = sys.argv[1]
pkg = sys.argv[2] if len(sys.argv) > 2 else None
sha1 = sys.argv[3].replace(":", "").lower() if len(sys.argv) > 3 else None

data = json.load(open(path, encoding="utf-8"))
ok = True

for c in data["client"]:
    name = c["client_info"]["android_client_info"]["package_name"]
    print("package:", name)
    if pkg and name != pkg:
        print("  X package does not match applicationId:", pkg)
        ok = False

    oauth = c.get("oauth_client", [])
    web = [o for o in oauth if o.get("client_type") == 3]
    android = [o for o in oauth if o.get("client_type") == 1]

    if not web:
        print("  X No Web client (client_type 3): Google provider not enabled or SHA-1 not added")
        ok = False
    else:
        print("  OK Web client ID:", web[0]["client_id"])

    hashes = [o["android_info"]["certificate_hash"] for o in android]
    print("  Registered SHA-1:", hashes or "none")
    if sha1 and sha1 not in hashes:
        print("  X Your SHA-1 is NOT in the registered list")
        ok = False

print()
print("ALL PASSED" if ok else "PROBLEMS FOUND")