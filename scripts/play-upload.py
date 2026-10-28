"""Upload a signed Android App Bundle to Google Play, INTERNAL track only, and verify it.

Used by .github/workflows/google-play.yml (OxiSoft CI/CD standard, skill oxisoft-app-ci-cd).

    python scripts/play-upload.py <app-release.aab> <versionName> <versionCode>

Env PLAY_PACKAGE: application id. Env PLAY_SA_FILE: path to the Play service-account JSON
(written from the PLAY_SA_JSON secret into the job's temp dir, removed after the job).

Release notes come from docs/store/release_notes/<versionName>.txt (1..500 chars): no notes
file, no upload, so a build never ships with placeholder text. Only the internal track is
ever touched; closed/open/production stay a human decision in the Play Console.
"""

import os
import sys
import time
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

PKG = os.environ["PLAY_PACKAGE"]
TRACK = "internal"

aab, name, expected_code = sys.argv[1], sys.argv[2], int(sys.argv[3])

notes_file = Path(__file__).resolve().parent.parent / "docs" / "store" / "release_notes" / f"{name}.txt"
if not notes_file.exists():
    sys.exit(f"missing release notes: {notes_file}")
NOTES = notes_file.read_text(encoding="utf-8").strip()
if not 0 < len(NOTES) <= 500:
    sys.exit(f"release notes must be 1..500 characters, got {len(NOTES)}")

creds = service_account.Credentials.from_service_account_file(
    os.environ["PLAY_SA_FILE"], scopes=["https://www.googleapis.com/auth/androidpublisher"]
)
edits = build("androidpublisher", "v3", credentials=creds, cache_discovery=False).edits()

eid = edits.insert(packageName=PKG, body={}).execute()["id"]
try:
    existing = {
        int(b["versionCode"])
        for b in edits.bundles().list(packageName=PKG, editId=eid).execute().get("bundles", [])
    }
    if expected_code in existing:
        # A re-run, or a version uploaded by hand (0.1.31 (32) was the console's first upload).
        print(f"::notice::versionCode {expected_code} is already on Play; nothing uploaded")
        edits.delete(packageName=PKG, editId=eid).execute()
        sys.exit(0)
    bundle = (
        edits.bundles()
        .upload(
            packageName=PKG,
            editId=eid,
            media_body=MediaFileUpload(aab, mimetype="application/octet-stream", resumable=True),
        )
        .execute()
    )
    code = int(bundle["versionCode"])
    if code != expected_code:
        raise RuntimeError(f"bundle has versionCode {code}, expected {expected_code}")
    print(f"uploaded bundle versionCode={code} sha1={bundle['sha1']}")
    edits.tracks().update(
        packageName=PKG,
        editId=eid,
        track=TRACK,
        body={
            "track": TRACK,
            "releases": [
                {
                    "name": name,
                    "versionCodes": [str(code)],
                    "status": "completed",
                    "releaseNotes": [{"language": "en-US", "text": NOTES}],
                }
            ],
        },
    ).execute()
    edits.commit(packageName=PKG, editId=eid).execute()
    print(f"committed: {name} ({code}) on track '{TRACK}'")
except Exception:
    edits.delete(packageName=PKG, editId=eid).execute()
    raise

# Read back from a fresh edit. The commit already succeeded, so a transient Play error
# here (503 seen right after a commit) is retried and never fails a good upload.
for attempt in range(5):
    try:
        eid = edits.insert(packageName=PKG, body={}).execute()["id"]
        track = edits.tracks().get(packageName=PKG, editId=eid, track=TRACK).execute()
        edits.delete(packageName=PKG, editId=eid).execute()
        break
    except Exception as e:  # noqa: BLE001
        print(f"read-back attempt {attempt + 1} failed: {e}")
        time.sleep(15 * (attempt + 1))
else:
    print("::warning::upload committed but the read-back did not complete; check the Play Console")
    sys.exit(0)
codes = [c for r in track.get("releases", []) for c in r.get("versionCodes", [])]
if str(code) not in codes:
    sys.exit(f"read-back: internal track has {codes}, not {code}")
print(f"verified: internal track now has {codes}")
