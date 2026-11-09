"""Download Google Play's signed universal APK of one build, for the GitHub release.

Used by .github/workflows/github-release.yml.

    python scripts/play-universal-apk.py <versionCode> <out.apk>

The APK is the one Play generates from the uploaded bundle and signs with the app signing
key, so it updates (and is updated by) the app installed from Google Play or F-Droid. Play
needs a while after the upload (google-play.yml, which runs on the same tag) before it has
the APK: this waits for it, up to WAIT_MINUTES.

Env PLAY_PACKAGE: application id. Env PLAY_SA_FILE: path to the Play service-account JSON.
"""

import os
import sys
import time

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaIoBaseDownload

PKG = os.environ["PLAY_PACKAGE"]
WAIT_MINUTES = 100

code, out = int(sys.argv[1]), sys.argv[2]

creds = service_account.Credentials.from_service_account_file(
    os.environ["PLAY_SA_FILE"], scopes=["https://www.googleapis.com/auth/androidpublisher"]
)
api = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

universal = None
deadline = time.monotonic() + WAIT_MINUTES * 60
while True:
    try:
        apks = api.generatedapks().list(packageName=PKG, versionCode=code).execute()
        universal = next(
            (g["generatedUniversalApk"] for g in apks.get("generatedApks", []) if g.get("generatedUniversalApk")),
            None,
        )
    except HttpError as error:
        # Play answers 404 until the bundle of this versionCode is processed.
        print(f"versionCode {code} not on Play yet ({error.status_code})", flush=True)
    if universal:
        break
    if time.monotonic() > deadline:
        sys.exit(f"Play has no universal APK for versionCode {code} after {WAIT_MINUTES} min")
    time.sleep(60)

request = api.generatedapks().download_media(
    packageName=PKG, versionCode=code, downloadId=universal["downloadId"]
)
with open(out, "wb") as f:
    downloader, done = MediaIoBaseDownload(f, request, chunksize=8 * 1024 * 1024), False
    while not done:
        _, done = downloader.next_chunk()
size = os.path.getsize(out)
if size < 1_000_000:
    sys.exit(f"{out} is only {size} bytes")
print(f"{out}: {size} bytes, versionCode {code}")
