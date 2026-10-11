import hmac, json, os, secrets, shlex, socket, subprocess, threading, time
from urllib.parse import parse_qs, urlsplit
from pywebpush import webpush, WebPushException
from py_vapid import Vapid
from cryptography.hazmat.primitives import serialization
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from webauthn import (generate_registration_options, verify_registration_response,
    generate_authentication_options, verify_authentication_response, options_to_json)
from webauthn.helpers import base64url_to_bytes as d, bytes_to_base64url as e
from webauthn.helpers.structs import (AuthenticatorSelectionCriteria, AuthenticatorAttachment,
    UserVerificationRequirement, PublicKeyCredentialDescriptor)

PIN = os.environ.get("PIN", "")
CMD = os.environ.get("SHUTDOWN_CMD", "touch /trigger/shutdown")
DELAY = float(os.environ.get("DELAY_SECONDS", "2"))
# RP_ID / ORIGIN are optional now: by default they are worked out from the address the phone used
RP_ID, ORIGIN = os.environ.get("RP_ID", ""), os.environ.get("ORIGIN", "")
DB = "/data/creds.json"
HTML = open(os.path.join(os.path.dirname(__file__), "index.html"), "rb").read()
SETUP_HTML = open(os.path.join(os.path.dirname(__file__), "setup.html"), "rb").read()
UV = UserVerificationRequirement.REQUIRED

try: creds = json.load(open(DB))
except Exception: creds = []
chal, tokens, vtokens, ctokens = {}, {}, {}, {}
save = lambda: json.dump(creds, open(DB, "w"))
desc = lambda: [PublicKeyCredentialDescriptor(id=d(c["id"])) for c in creds]

# ---- app files (installable web app) ----
_files = {"/sw.js": ("sw.js", "application/javascript"),
          "/manifest.webmanifest": ("manifest.webmanifest", "application/manifest+json"),
          "/icon-192.png": ("icon-192.png", "image/png"), "/icon-512.png": ("icon-512.png", "image/png"),
          "/apple-touch-icon.png": ("apple-touch-icon.png", "image/png")}
STATIC = {u: (open(os.path.join(os.path.dirname(__file__), f), "rb").read(), t) for u, (f, t) in _files.items()}

# ---- push notifications ----
SUBS_DB, VAPID_DB = "/data/subs.json", "/data/vapid.pem"
VAPID_SUB = os.environ.get("VAPID_SUB", "mailto:admin@example.com")
try: subs = json.load(open(SUBS_DB))
except Exception: subs = []
save_subs = lambda: json.dump(subs, open(SUBS_DB, "w"))
if not os.path.exists(VAPID_DB):
    _v = Vapid(); _v.generate_keys(); _v.save_key(VAPID_DB)
vapid = Vapid.from_file(VAPID_DB)
VAPID_PUB = e(vapid.public_key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint))


def notify(title, body, targets=None, tag="pc-status"):
    ok = False
    for sub in list(targets or subs):
        try:
            webpush(subscription_info=sub, data=json.dumps({"title": title, "body": body, "tag": tag}),
                    vapid_private_key=vapid, vapid_claims={"sub": VAPID_SUB})
            ok = True
        except WebPushException as ex:
            code = ex.response.status_code if ex.response is not None else 0
            if code in (404, 410) and sub in subs: subs.remove(sub); save_subs()   # phone unsubscribed
            else: print("push failed:", ex, flush=True)
        except Exception as ex:
            print("push error:", ex, flush=True)
    return ok


def announce():   # runs every time the container starts, i.e. when your PC is up and Docker is running
    time.sleep(5)
    for _ in range(6):   # the network may not be ready right after boot, so retry
        if not subs or notify("Your PC is on", "It just started. Tap to open your remote."): return
        time.sleep(20)



# ---- is the Windows watcher alive? (it touches /trigger/alive every ~2 s) ----
_alive = {"m": None, "t": 0.0}
def watcher_alive():
    try: m = os.stat("/trigger/alive").st_mtime_ns
    except OSError: return False
    now = time.monotonic()
    if m != _alive["m"]: _alive["m"], _alive["t"] = m, now   # changed = still running (no clock-skew issues)
    return now - _alive["t"] < 10
def _poll_alive():
    while True: watcher_alive(); time.sleep(2)


# ---- activity alerts: the Windows helper reports "PC used again after 5 min idle" ----
SETTINGS_DB = "/data/settings.json"
try: settings = json.load(open(SETTINGS_DB))
except Exception: settings = {}
settings.setdefault("activity_alerts", True)
settings.setdefault("idle_minutes", 5)
def save_settings(): json.dump(settings, open(SETTINGS_DB, "w"))

def write_config():   # tells the Windows helper how long "idle" is
    try:
        with open("/trigger/config.json.tmp", "w") as fh: json.dump({"idle_seconds": int(settings["idle_minutes"]) * 60}, fh)
        os.replace("/trigger/config.json.tmp", "/trigger/config.json")
    except Exception as ex: print("config error:", ex, flush=True)
if not settings.get("pin"):   # first run: make a random setup PIN (shown on the setup page, changeable there)
    settings["pin"] = os.environ.get("PIN") or "".join(secrets.choice("0123456789") for _ in range(6))
    save_settings()

def _info():   # written every minute by the Windows helper: Tailscale name / state
    try: return json.load(open("/trigger/info.json"))
    except Exception: return {}

def setup_state():
    i = _info(); dns = i.get("dns", "")
    return {"pc": i.get("pc", ""), "link": ("https://" + dns) if dns else "", "tailscale": i.get("state", "unknown"),
            "serving": bool(i.get("serving")), "helper": watcher_alive(), "pin": settings["pin"],
            "phones": len(creds), "notify": len(subs), "alerts": settings["activity_alerts"]}

def qr_svg(text):
    import io, qrcode, qrcode.image.svg
    img = qrcode.make(text, image_factory=qrcode.image.svg.SvgPathImage, box_size=10, border=2)
    buf = io.BytesIO(); img.save(buf); return buf.getvalue()

def _human(sec):
    m = max(int(sec) // 60, 1)
    return f"{m} min" if m < 60 else f"{m // 60} h {m % 60} min"

def _send_activity(sec):
    for _ in range(6):   # the network can be slow right after the PC wakes up
        if not subs or notify("Your PC is being used", f"It was idle for {_human(sec)} and just got mouse or keyboard activity.", tag="pc-activity"): return
        time.sleep(20)

def _activity_loop():
    try: os.remove("/trigger/activity.txt")   # ignore anything left over from before
    except OSError: pass
    while True:
        try:
            if os.path.exists("/trigger/activity.txt"):
                raw = open("/trigger/activity.txt").read().strip(); os.remove("/trigger/activity.txt")
                if settings["activity_alerts"] and subs:
                    threading.Thread(target=_send_activity, args=(float(raw or 300),), daemon=True).start()
        except Exception as ex: print("activity error:", ex, flush=True)
        time.sleep(2)


class H(BaseHTTPRequestHandler):
    def out(self, code=200, body=b"{}", ctype="application/json"):
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(body)

    def body(self): return self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()

    def local(self):   # True only for a browser on this PC itself (not via Tailscale)
        h = (self.headers.get("Host") or "").split(":")[0]
        proxied = any(self.headers.get(k) for k in ("Tailscale-User-Login", "X-Forwarded-For", "X-Forwarded-Host"))
        return h in ("localhost", "127.0.0.1") and not proxied

    def rp(self):   # WebAuthn relying-party id + origin, taken from the address the browser used
        if RP_ID and ORIGIN: return RP_ID, ORIGIN
        host = (self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or "").split(",")[0].strip()
        name = host.rsplit(":", 1)[0] if host.count(":") == 1 else host
        dns = _info().get("dns", "")
        if name in ("localhost", "127.0.0.1") and dns and any(self.headers.get(k) for k in ("Tailscale-User-Login", "X-Forwarded-For")):
            name = host = dns   # proxied by Tailscale but Host was rewritten: use the real name
        scheme = "http" if name in ("localhost", "127.0.0.1") else "https"
        return name, f"{scheme}://{host}"

    def pin_ok(self):
        pin = settings.get("pin", ""); ok = bool(pin) and hmac.compare_digest(self.headers.get("X-Pin", ""), pin)
        if not ok: time.sleep(1)
        return ok

    def do_GET(self):
        if self.path == "/": self.out(200, HTML, "text/html; charset=utf-8")
        elif self.path == "/setup":
            if self.local(): self.out(200, SETUP_HTML, "text/html; charset=utf-8")
            else: self.out(403, b"Open this page on your PC itself: http://localhost:8765/setup", "text/plain")
        elif self.path == "/api/setup":
            if not self.local(): return self.out(403)
            self.out(200, json.dumps(setup_state()).encode())
        elif self.path.startswith("/api/qr"):
            if not self.local(): return self.out(403)
            link = setup_state()["link"]
            if not link: return self.out(404)
            try: self.out(200, qr_svg(link), "image/svg+xml")
            except Exception as ex: print("qr error:", ex, flush=True); self.out(501)
        elif self.path in STATIC: self.out(200, *STATIC[self.path])
        elif self.path == "/api/push/key": self.out(200, json.dumps({"key": VAPID_PUB}).encode())
        elif self.path == "/api/ping": self.out(200, json.dumps({"enrolled": bool(creds), "watcher": watcher_alive(), "alerts": settings["activity_alerts"], "idle": settings["idle_minutes"], "message": os.path.exists("/trigger/message.on")}).encode())
        elif self.path.startswith("/api/stream?"):
            qs = parse_qs(urlsplit(self.path).query)
            exp = vtokens.get(qs.get("t", [""])[0], 0)
            prof = qs.get("q", ["med"])[0]
            if prof not in ("low", "med", "high"): prof = "med"
            if exp < time.time(): return self.out(401)
            # small send buffer + no Nagle delay: on a slow link we skip frames instead of queueing them (less lag)
            self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-store"); self.end_headers()
            last, beat = None, 0
            try:
                while time.time() < exp:
                    if time.time() - beat > 2:   # tell the Windows watcher someone is watching
                        open("/trigger/view", "w").write(prof); beat = time.time()
                    try:
                        st = os.stat("/trigger/screen.jpg"); key = (st.st_mtime_ns, st.st_size)
                        if key != last:
                            data = open("/trigger/screen.jpg", "rb").read(); last = key
                            self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n" % len(data) + data + b"\r\n")
                            self.wfile.flush(); continue
                    except OSError: pass
                    time.sleep(0.03)
            except (BrokenPipeError, ConnectionResetError): pass
        else: self.out(404)

    def do_POST(self):
        p = self.path
        try:
            if p == "/api/reg/options":
                if not self.pin_ok(): return self.out(401)
                o = generate_registration_options(rp_id=self.rp()[0], rp_name="PC Remote", user_id=b"owner",
                    user_name="owner", exclude_credentials=desc(),
                    authenticator_selection=AuthenticatorSelectionCriteria(
                        authenticator_attachment=AuthenticatorAttachment.PLATFORM, user_verification=UV))
                chal["reg"] = o.challenge
                self.out(200, options_to_json(o).encode())
            elif p == "/api/reg/verify":
                if not self.pin_ok(): return self.out(401)
                v = verify_registration_response(credential=self.body(), expected_challenge=chal.pop("reg"),
                    expected_rp_id=self.rp()[0], expected_origin=self.rp()[1], require_user_verification=True)
                creds.append({"id": e(v.credential_id), "pk": e(v.credential_public_key), "count": v.sign_count})
                save(); self.out()
            elif p == "/api/auth/options":
                if not creds: return self.out(409)
                o = generate_authentication_options(rp_id=self.rp()[0], allow_credentials=desc(), user_verification=UV)
                chal["auth"] = o.challenge
                self.out(200, options_to_json(o).encode())
            elif p == "/api/auth/verify":
                raw = self.body(); cid = json.loads(raw)["id"]
                c = next(c for c in creds if c["id"] == cid)
                v = verify_authentication_response(credential=raw, expected_challenge=chal.pop("auth"),
                    expected_rp_id=self.rp()[0], expected_origin=self.rp()[1], credential_public_key=d(c["pk"]),
                    credential_current_sign_count=c["count"], require_user_verification=True)
                c["count"] = v.new_sign_count; save()
                t = secrets.token_urlsafe(24); tokens[t] = time.time() + 60
                self.out(200, json.dumps({"token": t}).encode())
            elif p == "/api/push/subscribe":
                if tokens.pop(self.headers.get("X-Token", ""), 0) < time.time(): return self.out(401)
                sub = json.loads(self.body())
                subs[:] = [x for x in subs if x["endpoint"] != sub["endpoint"]] + [sub]; save_subs()
                threading.Thread(target=notify, args=("Notifications on", "You'll be told whenever your PC turns on.", [sub]), daemon=True).start()
                self.out()
            elif p == "/api/message":
                if tokens.pop(self.headers.get("X-Token", ""), 0) < time.time(): return self.out(401)
                if not watcher_alive(): return self.out(503)
                text = str(json.loads(self.body()).get("text", "")).strip()[:300]
                if not text: return self.out(400)
                with open("/trigger/message.tmp", "w", encoding="utf-8") as fh: fh.write(text)
                os.replace("/trigger/message.tmp", "/trigger/message.txt")   # atomic: watcher never sees half a file
                try: os.remove("/trigger/message.clear")
                except OSError: pass
                ctok = secrets.token_urlsafe(16); ctokens[ctok] = time.time() + 1800   # lets this phone remove it instantly
                self.out(200, json.dumps({"clear": ctok}).encode())
            elif p == "/api/message/clear":
                ok = ctokens.get(self.headers.get("X-Clear", ""), 0) >= time.time() or tokens.pop(self.headers.get("X-Token", ""), 0) >= time.time()
                if not ok: return self.out(401)
                if not watcher_alive(): return self.out(503)
                try: os.remove("/trigger/message.txt")
                except OSError: pass
                open("/trigger/message.clear", "w").close()
                self.out()
            elif p == "/api/setup/pin":
                if not self.local(): return self.out(403)
                pin = str(json.loads(self.body()).get("pin", "")).strip()
                if not (pin.isdigit() and 4 <= len(pin) <= 12): return self.out(400)
                settings["pin"] = pin; save_settings(); self.out()
            elif p == "/api/setup/reset":   # forget all registered phones
                if not self.local(): return self.out(403)
                creds.clear(); save(); self.out()
            elif p == "/api/idle":
                if tokens.pop(self.headers.get("X-Token", ""), 0) < time.time(): return self.out(401)
                m = int(json.loads(self.body()).get("minutes", 0))
                if m not in (1, 2, 5, 10, 15, 30): return self.out(400)
                settings["idle_minutes"] = m; save_settings(); write_config()
                self.out(200, json.dumps({"minutes": m}).encode())
            elif p == "/api/power":   # restart or lock the PC (the Windows helper carries it out)
                if tokens.pop(self.headers.get("X-Token", ""), 0) < time.time(): return self.out(401)
                if not watcher_alive(): return self.out(503)
                act = str(json.loads(self.body()).get("action", ""))
                if act not in ("restart", "lock"): return self.out(400)
                with open("/trigger/action.tmp", "w") as fh: fh.write(act)
                os.replace("/trigger/action.tmp", "/trigger/action.txt")
                self.out()
            elif p == "/api/alerts":
                if tokens.pop(self.headers.get("X-Token", ""), 0) < time.time(): return self.out(401)
                settings["activity_alerts"] = bool(json.loads(self.body()).get("on")); save_settings()
                self.out(200, json.dumps({"on": settings["activity_alerts"]}).encode())
            elif p == "/api/view/start":
                if tokens.pop(self.headers.get("X-Token", ""), 0) < time.time(): return self.out(401)
                if not watcher_alive(): return self.out(503)   # helper on the PC isn't running
                t = secrets.token_urlsafe(24); vtokens[t] = time.time() + 600   # 10 minutes
                self.out(200, json.dumps({"token": t}).encode())
            elif p == "/api/shutdown":
                if tokens.pop(self.headers.get("X-Token", ""), 0) < time.time(): return self.out(401)
                if not watcher_alive(): return self.out(503)   # helper on the PC isn't running
                threading.Timer(DELAY, lambda: subprocess.Popen(shlex.split(CMD))).start(); self.out()
            else: self.out(404)
        except Exception as ex:
            print("error:", p, ex, flush=True); self.out(400)

    def log_message(self, *a): pass


if __name__ == "__main__":
    print("PC Remote on :8080", flush=True)
    threading.Thread(target=announce, daemon=True).start()
    write_config()
    threading.Thread(target=_poll_alive, daemon=True).start()
    threading.Thread(target=_activity_loop, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
