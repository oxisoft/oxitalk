"""TLS on :8448 in front of the test homeserver's plain :8008, for lk-jwt-service only.

lk-jwt-service checks a client's OpenID token at https://<server name>:8448/_matrix/federation/
v1/openid/userinfo (always HTTPS, port 8448 for a server name without a port). The test
homeservers are `localhost` and speak plain HTTP on 8008, so this proxy, in the same pod, gives
them that address with a throwaway self-signed certificate (lk-jwt-service runs with
LIVEKIT_INSECURE_SKIP_VERIFY_TLS). Test only.
"""

import asyncio
import ssl
import subprocess
import tempfile
from pathlib import Path

UPSTREAM = ("127.0.0.1", 8008)
LISTEN = ("0.0.0.0", 8448)


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, ssl.SSLError):
        pass
    finally:
        writer.close()


async def handle(client_reader, client_writer) -> None:
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection(*UPSTREAM)
    except OSError:
        client_writer.close()
        return
    await asyncio.gather(
        pipe(client_reader, upstream_writer), pipe(upstream_reader, client_writer)
    )


async def main() -> None:
    folder = Path(tempfile.mkdtemp())
    cert, key = folder / "cert.pem", folder / "key.pem"
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
         "-subj", "/CN=localhost", "-keyout", str(key), "-out", str(cert)],
        check=True, capture_output=True,
    )
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server = await asyncio.start_server(handle, *LISTEN, ssl=context)
    print(f"openid TLS proxy on {LISTEN[1]} -> {UPSTREAM[1]}", flush=True)
    async with server:
        await server.serve_forever()


asyncio.run(main())
