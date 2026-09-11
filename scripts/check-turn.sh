#!/usr/bin/env bash
set -euo pipefail

# check-turn.sh — app-uafhængig verifikation af den delte TURN-tjeneste (ADR 0003).
#
# Tjekker, udefra og uden en app:
#   1. at værtsnavnet opløses
#   2. at TCP 3478 svarer
#   3. STUN binding (UDP) — coturn lytter og svarer klienter
#   4. Allocate uden credentials — skal afvises (ellers er relayen åben)
#   5. Allocate med HMAC-credentials — relay-allokering + MESSAGE-INTEGRITY
#   6. Allocate med forkert hemmelighed — skal afvises
#
# Tjek 3-5 er dem, der faktisk beviser at TURN virker: en STUN-only-test
# forbinder direkte og rører aldrig relayeren.
#
# Brug:
#   ./scripts/check-turn.sh                                  # turn.gihc.online
#   ./scripts/check-turn.sh --host 65.109.233.92             # før DNS er slået igennem
#   ./scripts/check-turn.sh --secret lofts-test-hemmelighed  # uden pass
#
# Hemmeligheden hentes fra `pass turn/static-auth-secret`, hvis den ikke er givet.

TURN_HOST="${TURN_HOST:-turn.gihc.online}"
TURN_PORT="${TURN_PORT:-3478}"
TURN_TTL="${TURN_TTL:-3600}"
TURN_TIMEOUT="${TURN_TIMEOUT:-5}"
TURN_SKIP_NEGATIVE="${TURN_SKIP_NEGATIVE:-0}"
TURN_SECRET="${TURN_SECRET:-}"
PASS_ENTRY="${PASS_ENTRY:-turn/static-auth-secret}"

usage() {
    cat <<'EOF'
Verificerer den delte TURN-tjeneste udefra (STUN + relay-allokering + negativt tjek).

Brug:
  ./scripts/check-turn.sh [--host VÆRT] [--port PORT] [--secret HEM] [--skip-negative]

Miljø: TURN_HOST (turn.gihc.online), TURN_PORT (3478), TURN_SECRET
       (ellers `pass turn/static-auth-secret`), TURN_TIMEOUT (5).
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--host)        TURN_HOST="$2"; shift 2 ;;
        -p|--port)        TURN_PORT="$2"; shift 2 ;;
        -s|--secret)      TURN_SECRET="$2"; shift 2 ;;
        --ttl)            TURN_TTL="$2"; shift 2 ;;
        --timeout)        TURN_TIMEOUT="$2"; shift 2 ;;
        --skip-negative)  TURN_SKIP_NEGATIVE=1; shift ;;
        --help)           usage; exit 0 ;;
        *) echo "ukendt argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$TURN_SECRET" ]; then
    if ! TURN_SECRET="$(pass "$PASS_ENTRY" 2>/dev/null)"; then
        echo "fejl: kunne ikke læse 'pass ${PASS_ENTRY}' — brug --secret" >&2
        exit 1
    fi
fi

export TURN_HOST TURN_PORT TURN_TTL TURN_TIMEOUT TURN_SKIP_NEGATIVE TURN_SECRET

python3 - <<'PY'
import base64, hashlib, hmac, os, socket, struct, sys, time

MAGIC = 0x2112A442

BINDING_REQUEST, BINDING_SUCCESS = 0x0001, 0x0101
ALLOCATE_REQUEST, ALLOCATE_SUCCESS = 0x0003, 0x0103

A_MAPPED = 0x0001
A_USERNAME = 0x0006
A_MI = 0x0008
A_ERROR = 0x0009
A_LIFETIME = 0x000D
A_REALM = 0x0014
A_NONCE = 0x0015
A_XOR_RELAYED = 0x0016
A_REQ_TRANSPORT = 0x0019
A_XOR_MAPPED = 0x0020
A_SOFTWARE = 0x8022

UDP_TRANSPORT = struct.pack("!BBBB", 17, 0, 0, 0)

results = []


def report(ok, text):
    results.append(bool(ok))
    print(f"  [{'ok' if ok else 'FEJL'}] {text}")


def pack_attr(atype, value):
    padding = b"\x00" * ((4 - len(value) % 4) % 4)
    return struct.pack("!HH", atype, len(value)) + value + padding


def build(msgtype, txid, attributes, key=None):
    body = b"".join(pack_attr(t, v) for t, v in attributes)
    if key is None:
        return struct.pack("!HHI", msgtype, len(body), MAGIC) + txid + body
    # MESSAGE-INTEGRITY dækker hele beskeden inkl. det attr, der beskriver den:
    # headerens længdefelt skal derfor tælle MI-attributtet med (4 + 20 bytes).
    header = struct.pack("!HHI", msgtype, len(body) + 24, MAGIC) + txid
    message = header + body
    return message + pack_attr(A_MI, hmac.new(key, message, hashlib.sha1).digest())


def parse(data):
    if len(data) < 20:
        raise ValueError("for kort STUN-besked")
    msgtype, length, cookie = struct.unpack("!HHI", data[:8])
    if cookie != MAGIC:
        raise ValueError("forkert magic cookie — er det en STUN-server?")
    txid = data[8:20]
    attrs = []
    offset = 20
    end = min(20 + length, len(data))
    while offset + 4 <= end:
        atype, alen = struct.unpack("!HH", data[offset:offset + 4])
        attrs.append((atype, data[offset + 4:offset + 4 + alen], offset))
        offset += 4 + alen + ((4 - alen % 4) % 4)
    return msgtype, txid, attrs


def first(attrs, atype):
    for a, value, _ in attrs:
        if a == atype:
            return value
    return None


def error_code(value):
    return value[2] * 100 + value[3] if value and len(value) >= 4 else None


def decode_address(value, txid, xor):
    if not value or len(value) < 8:
        return "?"
    family = value[1]
    port = struct.unpack("!H", value[2:4])[0]
    raw = value[4:]
    if xor:
        port ^= MAGIC >> 16
        mask = struct.pack("!I", MAGIC) + txid
        raw = bytes(b ^ mask[i % 16] for i, b in enumerate(raw))
    if family == 0x01:
        return f"{socket.inet_ntoa(raw[:4])}:{port}"
    if family == 0x02:
        return f"[{socket.inet_ntop(socket.AF_INET6, raw[:16])}]:{port}"
    return "?"


def integrity_ok(data, attrs, key):
    for atype, value, offset in attrs:
        if atype == A_MI:
            patched = bytearray(data[:offset])
            patched[2:4] = struct.pack("!H", offset - 20 + 4 + len(value))
            expected = hmac.new(key, bytes(patched), hashlib.sha1).digest()
            return hmac.compare_digest(expected, value)
    return False


def credentials(secret, ttl):
    """TURN REST API: username er et udløbstidspunkt, password er HMAC-SHA1."""
    username = str(int(time.time()) + ttl)
    digest = hmac.new(secret.encode(), username.encode(), hashlib.sha1).digest()
    return username, base64.b64encode(digest).decode()


def long_term_key(username, realm, password):
    return hashlib.md5(f"{username}:{realm}:{password}".encode()).digest()


def transact(sock, payload, timeout, tries=2):
    last_error = None
    for _ in range(tries):
        sock.send(payload)
        try:
            return sock.recv(4096)
        except socket.timeout as exc:
            last_error = exc
    raise RuntimeError(f"intet svar fra TURN-serveren ({last_error})")


def main():
    host = os.environ["TURN_HOST"]
    port = int(os.environ["TURN_PORT"])
    secret = os.environ["TURN_SECRET"]
    ttl = int(os.environ["TURN_TTL"])
    timeout = float(os.environ["TURN_TIMEOUT"])
    skip_negative = os.environ.get("TURN_SKIP_NEGATIVE") == "1"

    print(f"==> TURN {host}:{port}")
    try:
        ip = socket.gethostbyname(host)
    except OSError as exc:
        report(False, f"kunne ikke opløse {host}: {exc}")
        return 1
    print(f"    {host} → {ip}")

    try:
        with socket.create_connection((ip, port), timeout=timeout):
            report(True, f"TCP {port} svarer")
    except OSError as exc:
        report(False, f"TCP {port}: {exc}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.connect((ip, port))

    # 1. STUN binding — beviser at coturn svarer udefra.
    try:
        data = transact(sock, build(BINDING_REQUEST, os.urandom(12), []), timeout)
        msgtype, txid, attrs = parse(data)
    except (OSError, RuntimeError, ValueError) as exc:
        report(False, f"STUN binding: {exc}")
        return 1

    if msgtype != BINDING_SUCCESS:
        report(False, f"STUN binding: uventet svar 0x{msgtype:04x}")
    else:
        mapped = first(attrs, A_XOR_MAPPED) or first(attrs, A_MAPPED)
        software = first(attrs, A_SOFTWARE)
        text = f"STUN binding ok (serveren ser os som {decode_address(mapped, txid, True)})"
        if software:
            text += f"; software={software.decode(errors='replace')}"
        report(True, text)

    # 2. Allocate uden credentials — skal afvises, ellers er relayen åben.
    try:
        data = transact(
            sock,
            build(ALLOCATE_REQUEST, os.urandom(12), [(A_REQ_TRANSPORT, UDP_TRANSPORT)]),
            timeout,
        )
        msgtype, txid, attrs = parse(data)
    except (OSError, RuntimeError, ValueError) as exc:
        report(False, f"Allocate uden credentials: {exc}")
        return 1

    realm = first(attrs, A_REALM)
    nonce = first(attrs, A_NONCE)
    code = error_code(first(attrs, A_ERROR))

    if msgtype == ALLOCATE_SUCCESS:
        report(False, "relayen allokerede UDEN credentials — TURN står åbent")
        return 1
    if code != 401 or not realm or not nonce:
        report(False, f"Allocate uden credentials: uventet svar (type 0x{msgtype:04x}, fejlkode {code})")
        return 1
    report(True, f"Allocate uden credentials afvist (401, realm={realm.decode(errors='replace')})")

    # 3. Allocate med HMAC-credentials (TURN REST API) — det egentlige bevis.
    username, password = credentials(secret, ttl)
    key = long_term_key(username, realm.decode(errors="replace"), password)

    for attempt in range(2):
        request = build(
            ALLOCATE_REQUEST,
            os.urandom(12),
            [
                (A_REQ_TRANSPORT, UDP_TRANSPORT),
                (A_USERNAME, username.encode()),
                (A_REALM, realm),
                (A_NONCE, nonce),
            ],
            key=key,
        )
        try:
            data = transact(sock, request, timeout)
            msgtype, txid, attrs = parse(data)
        except (OSError, RuntimeError, ValueError) as exc:
            report(False, f"Allocate med credentials: {exc}")
            return 1

        if msgtype == ALLOCATE_SUCCESS:
            relayed = first(attrs, A_XOR_RELAYED)
            lifetime = first(attrs, A_LIFETIME)
            seconds = struct.unpack("!I", lifetime)[0] if lifetime else None
            software = first(attrs, A_SOFTWARE)
            verified = integrity_ok(data, attrs, key)
            text = (
                f"Allocate med HMAC-credentials ok "
                f"(relay={decode_address(relayed, txid, True)}, lifetime={seconds}s"
                f", MESSAGE-INTEGRITY {'verificeret' if verified else 'kunne IKKE verificeres'}"
            )
            if software:
                text += f"; software={software.decode(errors='replace')}"
            report(verified, text + ")")
            break

        code = error_code(first(attrs, A_ERROR))
        if code == 438 and first(attrs, A_NONCE):  # stale nonce — prøv igen
            nonce = first(attrs, A_NONCE)
            continue
        report(False, f"Allocate med HMAC-credentials afvist (fejlkode {code})")
        return 1

    # 4. Forkert hemmelighed må ikke give adgang. Testen kører på en frisk
    #    socket (ny 5-tuple): en ny Allocate på samme 5-tuple afvises med 437
    #    (Allocation Mismatch) før auth, så den ville ikke sige noget om
    #    hemmeligheden.
    if not skip_negative:
        wrong = base64.b64encode(
            hmac.new(b"forkert-hemmelighed", username.encode(), hashlib.sha1).digest()
        ).decode()
        neg_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        neg_sock.connect((ip, port))
        try:
            data = transact(
                neg_sock,
                build(ALLOCATE_REQUEST, os.urandom(12), [(A_REQ_TRANSPORT, UDP_TRANSPORT)]),
                timeout,
            )
            _, _, neg_attrs = parse(data)
            neg_realm = first(neg_attrs, A_REALM) or realm
            neg_nonce = first(neg_attrs, A_NONCE) or nonce

            request = build(
                ALLOCATE_REQUEST,
                os.urandom(12),
                [
                    (A_REQ_TRANSPORT, UDP_TRANSPORT),
                    (A_USERNAME, username.encode()),
                    (A_REALM, neg_realm),
                    (A_NONCE, neg_nonce),
                ],
                key=long_term_key(username, neg_realm.decode(errors="replace"), wrong),
            )
            data = transact(neg_sock, request, timeout)
            msgtype, _, attrs = parse(data)
        except (OSError, RuntimeError, ValueError) as exc:
            report(False, f"Allocate med forkert hemmelighed: {exc}")
            return 1
        finally:
            neg_sock.close()

        if msgtype == ALLOCATE_SUCCESS:
            report(False, "forkert hemmelighed blev accepteret — auth virker ikke")
        else:
            code = error_code(first(attrs, A_ERROR))
            report(code == 401, f"Allocate med forkert hemmelighed afvist ({code})")

    return 0 if all(results) else 1


sys.exit(main())
PY
