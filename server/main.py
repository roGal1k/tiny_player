import os
import time
import json
import hashlib
import secrets
from typing import Optional, List, Dict, Any

from fastapi import FastAPI, Depends, HTTPException, status, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import jwt
import aiosqlite
import httpx
import urllib.parse

DB_PATH = os.environ.get("DB_PATH", "/var/lib/core_player/core_player.db")
USER_FILES_DIR = os.environ.get("USER_FILES_DIR", "/var/lib/core_player/user_files")
BACKUPS_DIR = os.path.join(USER_FILES_DIR, "backups")
JWT_SECRET = os.environ.get("JWT_SECRET", "core_player_super_secret_jwt_key_2026_xyz")
JWT_ALGORITHM = "HS256"

app = FastAPI(title="CorePlayer Sync Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Range", "Content-Length", "Accept-Ranges", "Content-Disposition"],
)

# ----------------- DB Initialization -----------------

async def get_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    db = await aiosqlite.connect(DB_PATH)
    db.row_factory = aiosqlite.Row
    try:
        yield db
    finally:
        await db.close()

shared_proxy_client: Optional[httpx.AsyncClient] = None

@app.on_event("startup")
async def startup_event():
    global shared_proxy_client
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    os.makedirs(USER_FILES_DIR, exist_ok=True)
    os.makedirs(BACKUPS_DIR, exist_ok=True)
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                salt TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS user_sync (
                user_id INTEGER PRIMARY KEY,
                library_json TEXT DEFAULT '[]',
                artists_json TEXT DEFAULT '[]',
                playlists_json TEXT DEFAULT '[]',
                history_json TEXT DEFAULT '[]',
                settings_json TEXT DEFAULT '{}',
                updated_at INTEGER NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
        """)
        try:
            await db.execute("ALTER TABLE user_sync ADD COLUMN artists_json TEXT DEFAULT '[]'")
        except Exception:
            pass
        try:
            await db.execute("ALTER TABLE user_sync ADD COLUMN cached_json TEXT DEFAULT '[]'")
        except Exception:
            pass
        await db.commit()

    shared_proxy_client = httpx.AsyncClient(
        follow_redirects=True,
        timeout=httpx.Timeout(30.0, connect=6.0),
        limits=httpx.Limits(max_keepalive_connections=50, max_connections=200, keepalive_expiry=120.0),
    )

@app.on_event("shutdown")
async def shutdown_event():
    global shared_proxy_client
    if shared_proxy_client:
        await shared_proxy_client.aclose()

# ----------------- Auth Helpers -----------------

def hash_password(password: str, salt: str = None) -> tuple[str, str]:
    if salt is None:
        salt = secrets.token_hex(16)
    hashed = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 100000)
    return hashed.hex(), salt

def verify_password(password: str, salt: str, expected_hash: str) -> bool:
    hashed, _ = hash_password(password, salt)
    return secrets.compare_digest(hashed, expected_hash)

def create_access_token(user_id: int, username: str) -> str:
    payload = {
        "sub": str(user_id),
        "username": username,
        "exp": time.time() + 60 * 60 * 24 * 365,  # 1 year token
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

async def get_current_user(request: Request, db: aiosqlite.Connection = Depends(get_db)) -> dict:
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
        )
    token = auth_header.split(" ", 1)[1]
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = int(payload.get("sub"))
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )

    async with db.execute("SELECT id, username FROM users WHERE id = ?", (user_id,)) as cursor:
        row = await cursor.fetchone()
        if not row:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
        return {"id": row["id"], "username": row["username"]}

# ----------------- User Files & Backups -----------------

def save_user_data_file(username: str, data: dict) -> str:
    try:
        os.makedirs(USER_FILES_DIR, exist_ok=True)
        os.makedirs(BACKUPS_DIR, exist_ok=True)
        clean = username.strip().lower()
        file_path = os.path.join(USER_FILES_DIR, f"{clean}_data.json")
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        timestamp_str = time.strftime("%Y%m%d_%H%M%S")
        backup_path = os.path.join(BACKUPS_DIR, f"{clean}_{timestamp_str}.json")
        try:
            with open(backup_path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception:
            pass
        return file_path
    except Exception as e:
        print(f"[CorePlayer Server] Error saving user file: {e}")
        return ""

# ----------------- Pydantic Models -----------------

class AuthRequest(BaseModel):
    username: str
    password: str

class SyncPushRequest(BaseModel):
    library: List[Dict[str, Any]] = []
    artists: List[Dict[str, Any]] = []
    cached_tracks: List[Dict[str, Any]] = []
    playlists: List[Dict[str, Any]] = []
    history: List[Dict[str, Any]] = []
    settings: Dict[str, Any] = {}
    client_timestamp: Optional[int] = None

# ----------------- Routes -----------------

@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "core_player_sync", "version": "1.0.0"}

@app.post("/api/auth/register")
async def register(req: AuthRequest, db: aiosqlite.Connection = Depends(get_db)):
    clean_username = req.username.strip().lower()
    if len(clean_username) < 3:
        raise HTTPException(status_code=400, detail="Username must be at least 3 characters")
    if len(req.password) < 4:
        raise HTTPException(status_code=400, detail="Password must be at least 4 characters")

    async with db.execute("SELECT id FROM users WHERE username = ?", (clean_username,)) as cursor:
        if await cursor.fetchone():
            raise HTTPException(status_code=400, detail="Username already exists")

    pwd_hash, salt = hash_password(req.password)
    cursor = await db.execute(
        "INSERT INTO users (username, salt, password_hash) VALUES (?, ?, ?)",
        (clean_username, salt, pwd_hash),
    )
    user_id = cursor.lastrowid
    now_ms = int(time.time() * 1000)
    await db.execute(
        "INSERT INTO user_sync (user_id, library_json, artists_json, playlists_json, history_json, settings_json, updated_at) VALUES (?, '[]', '[]', '[]', '[]', '{}', ?)",
        (user_id, now_ms),
    )
    await db.commit()

    token = create_access_token(user_id, clean_username)
    return {"token": token, "username": clean_username, "user_id": user_id}

@app.post("/api/auth/login")
async def login(req: AuthRequest, db: aiosqlite.Connection = Depends(get_db)):
    clean_username = req.username.strip().lower()
    async with db.execute("SELECT id, username, salt, password_hash FROM users WHERE username = ?", (clean_username,)) as cursor:
        row = await cursor.fetchone()
        if not row or not verify_password(req.password, row["salt"], row["password_hash"]):
            raise HTTPException(status_code=401, detail="Invalid username or password")

        token = create_access_token(row["id"], row["username"])
        return {"token": token, "username": row["username"], "user_id": row["id"]}

@app.get("/api/auth/me")
async def get_me(user: dict = Depends(get_current_user)):
    return user

@app.get("/api/sync/pull")
async def sync_pull(user: dict = Depends(get_current_user), db: aiosqlite.Connection = Depends(get_db)):
    user_id = user["id"]
    async with db.execute(
        "SELECT * FROM user_sync WHERE user_id = ?",
        (user_id,),
    ) as cursor:
        row = await cursor.fetchone()
        if not row:
            return {
                "library": [],
                "artists": [],
                "playlists": [],
                "history": [],
                "settings": {},
                "updated_at": 0,
            }

        row_keys = row.keys()
        return {
            "library": json.loads(row["library_json"] or "[]"),
            "artists": json.loads(row["artists_json"] or "[]") if "artists_json" in row_keys and row["artists_json"] else [],
            "cached_tracks": json.loads(row["cached_json"] or "[]") if "cached_json" in row_keys and row["cached_json"] else [],
            "playlists": json.loads(row["playlists_json"] or "[]"),
            "history": json.loads(row["history_json"] or "[]"),
            "settings": json.loads(row["settings_json"] or "{}"),
            "updated_at": row["updated_at"],
        }

@app.post("/api/sync/push")
async def sync_push(
    req: SyncPushRequest,
    user: dict = Depends(get_current_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    user_id = user["id"]
    now_ms = int(time.time() * 1000)

    # 1. Fetch current server state
    async with db.execute(
        "SELECT * FROM user_sync WHERE user_id = ?",
        (user_id,),
    ) as cursor:
        row = await cursor.fetchone()

    row_keys = row.keys() if row else []
    server_library: List[Dict[str, Any]] = json.loads(row["library_json"] or "[]") if row else []
    server_artists: List[Dict[str, Any]] = json.loads(row["artists_json"] or "[]") if row and "artists_json" in row_keys and row["artists_json"] else []
    server_cached: List[Dict[str, Any]] = json.loads(row["cached_json"] or "[]") if row and "cached_json" in row_keys and row["cached_json"] else []
    server_playlists: List[Dict[str, Any]] = json.loads(row["playlists_json"] or "[]") if row else []
    server_history: List[Dict[str, Any]] = json.loads(row["history_json"] or "[]") if row else []
    server_settings: Dict[str, Any] = json.loads(row["settings_json"] or "{}") if row else {}

    # 2. Merge libraries by unique key: (providerId, id)
    seen_keys = set()
    merged_library = []

    # First add client tracks
    for t in req.library:
        key = (t.get("providerId") or t.get("provider_id"), str(t.get("id")))
        if key[0] and key[1] and key not in seen_keys:
            seen_keys.add(key)
            merged_library.append(t)

    # Add any server tracks not present in client
    for t in server_library:
        key = (t.get("providerId") or t.get("provider_id"), str(t.get("id")))
        if key[0] and key[1] and key not in seen_keys:
            seen_keys.add(key)
            merged_library.append(t)

    # 3. Merge cached tracks by unique key: (providerId, id)
    seen_cached_keys = set()
    merged_cached = []

    for t in req.cached_tracks:
        key = (t.get("providerId") or t.get("provider_id"), str(t.get("id")))
        if key[0] and key[1] and key not in seen_cached_keys:
            seen_cached_keys.add(key)
            merged_cached.append(t)

    for t in server_cached:
        key = (t.get("providerId") or t.get("provider_id"), str(t.get("id")))
        if key[0] and key[1] and key not in seen_cached_keys:
            seen_cached_keys.add(key)
            merged_cached.append(t)

    # 4. Merge artists by name (case-insensitive)
    seen_artists = set()
    merged_artists = []

    for a in req.artists:
        name = (a.get("name") or "").strip().lower()
        if name and name not in seen_artists:
            seen_artists.add(name)
            merged_artists.append(a)

    for a in server_artists:
        name = (a.get("name") or "").strip().lower()
        if name and name not in seen_artists:
            seen_artists.add(name)
            merged_artists.append(a)

    # Merge settings (client overrides server)
    merged_settings = {**server_settings, **req.settings}
    merged_playlists = req.playlists if req.playlists else server_playlists
    merged_history = req.history if req.history else server_history

    # Save to SQLite DB
    await db.execute("""
        INSERT INTO user_sync (user_id, library_json, artists_json, cached_json, playlists_json, history_json, settings_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
            library_json = excluded.library_json,
            artists_json = excluded.artists_json,
            cached_json = excluded.cached_json,
            playlists_json = excluded.playlists_json,
            history_json = excluded.history_json,
            settings_json = excluded.settings_json,
            updated_at = excluded.updated_at
    """, (
        user_id,
        json.dumps(merged_library),
        json.dumps(merged_artists),
        json.dumps(merged_cached),
        json.dumps(merged_playlists),
        json.dumps(merged_history),
        json.dumps(merged_settings),
        now_ms,
    ))
    await db.commit()

    # Save user file and backup to VPS disk
    full_user_data = {
        "version": 1,
        "username": user["username"],
        "updated_at": now_ms,
        "exported_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "library": merged_library,
        "artists": merged_artists,
        "cached_tracks": merged_cached,
        "playlists": merged_playlists,
        "history": merged_history,
        "settings": merged_settings,
    }
    save_user_data_file(user["username"], full_user_data)

    return {
        "status": "success",
        "library": merged_library,
        "artists": merged_artists,
        "cached_tracks": merged_cached,
        "playlists": merged_playlists,
        "settings": merged_settings,
        "updated_at": now_ms,
    }

# ----------------- User Profile File Endpoints -----------------

@app.get("/api/user/file/info")
async def get_user_file_info(user: dict = Depends(get_current_user), db: aiosqlite.Connection = Depends(get_db)):
    clean_username = user["username"].strip().lower()
    file_path = os.path.join(USER_FILES_DIR, f"{clean_username}_data.json")
    exists = os.path.isfile(file_path)
    file_size = os.path.getsize(file_path) if exists else 0
    mtime = int(os.path.getmtime(file_path) * 1000) if exists else 0

    async with db.execute("SELECT * FROM user_sync WHERE user_id = ?", (user["id"],)) as cursor:
        row = await cursor.fetchone()
        row_keys = row.keys() if row else []
        tracks_count = len(json.loads(row["library_json"])) if row and row["library_json"] else 0
        artists_count = len(json.loads(row["artists_json"])) if row and "artists_json" in row_keys and row["artists_json"] else 0
        cached_count = len(json.loads(row["cached_json"])) if row and "cached_json" in row_keys and row["cached_json"] else 0
        updated_at = row["updated_at"] if row else 0

    return {
        "filename": f"{clean_username}_data.json",
        "exists": exists,
        "size_bytes": file_size,
        "mtime_ms": mtime,
        "updated_at": updated_at,
        "tracks_count": tracks_count,
        "artists_count": artists_count,
        "cached_count": cached_count,
    }

@app.get("/api/user/file/download")
async def download_user_file(user: dict = Depends(get_current_user), db: aiosqlite.Connection = Depends(get_db)):
    clean_username = user["username"].strip().lower()
    file_path = os.path.join(USER_FILES_DIR, f"{clean_username}_data.json")

    if not os.path.isfile(file_path):
        async with db.execute("SELECT * FROM user_sync WHERE user_id = ?", (user["id"],)) as cursor:
            row = await cursor.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="No user data found")
            row_keys = row.keys()
            full_user_data = {
                "version": 1,
                "username": user["username"],
                "updated_at": row["updated_at"],
                "exported_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "library": json.loads(row["library_json"] or "[]"),
                "artists": json.loads(row["artists_json"] or "[]") if "artists_json" in row_keys and row["artists_json"] else [],
                "cached_tracks": json.loads(row["cached_json"] or "[]") if "cached_json" in row_keys and row["cached_json"] else [],
                "playlists": json.loads(row["playlists_json"] or "[]"),
                "history": json.loads(row["history_json"] or "[]"),
                "settings": json.loads(row["settings_json"] or "{}"),
            }
            save_user_data_file(user["username"], full_user_data)

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    filename = f"{clean_username}_data.json"
    return Response(
        content=content,
        media_type="application/json",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )

@app.post("/api/user/file/upload")
async def upload_user_file(request: Request, user: dict = Depends(get_current_user), db: aiosqlite.Connection = Depends(get_db)):
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    library = body.get("library") or []
    artists = body.get("artists") or body.get("favorite_artists") or []
    playlists = body.get("playlists") or []
    history = body.get("history") or []
    settings = body.get("settings") or {}
    now_ms = int(time.time() * 1000)

    await db.execute("""
        INSERT INTO user_sync (user_id, library_json, artists_json, playlists_json, history_json, settings_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
            library_json = excluded.library_json,
            artists_json = excluded.artists_json,
            playlists_json = excluded.playlists_json,
            history_json = excluded.history_json,
            settings_json = excluded.settings_json,
            updated_at = excluded.updated_at
    """, (
        user["id"],
        json.dumps(library),
        json.dumps(artists),
        json.dumps(playlists),
        json.dumps(history),
        json.dumps(settings),
        now_ms,
    ))
    await db.commit()

    full_user_data = {
        "version": 1,
        "username": user["username"],
        "updated_at": now_ms,
        "exported_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "library": library,
        "artists": artists,
        "playlists": playlists,
        "history": history,
        "settings": settings,
    }
    save_user_data_file(user["username"], full_user_data)

    return {
        "status": "success",
        "tracks_count": len(library),
        "artists_count": len(artists),
        "updated_at": now_ms,
    }

# ----------------- CORS Stream & HTTP Proxy -----------------

DEFAULT_PROXY_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept": "*/*",
    "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
    "X-Forwarded-For": "85.249.20.1",
    "X-Real-IP": "85.249.20.1",
    "CF-Connecting-IP": "85.249.20.1",
}

HITMO_MIRRORS = [
    "https://ru.hitmoz.org",
    "https://rur.hitmotop.com",
    "https://rus.hitmotop.com",
]

def get_candidate_stream_urls(target_url: str) -> list[str]:
    candidates = [target_url]
    if "/get/music/" in target_url:
        parsed = urllib.parse.urlparse(target_url)
        for mirror in HITMO_MIRRORS:
            mirror_parsed = urllib.parse.urlparse(mirror)
            alt = urllib.parse.urlunparse((
                mirror_parsed.scheme,
                mirror_parsed.netloc,
                parsed.path,
                parsed.params,
                parsed.query,
                parsed.fragment,
            ))
            if alt not in candidates:
                candidates.append(alt)
    return candidates

@app.api_route("/api/proxy/stream", methods=["GET", "HEAD", "OPTIONS"])
async def proxy_stream(request: Request, url: str = Query(..., description="Target stream URL")):
    if request.method == "OPTIONS":
        return Response(
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
                "Access-Control-Allow-Headers": "Range, Content-Type, Accept, Authorization",
                "Access-Control-Expose-Headers": "Content-Range, Content-Length, Accept-Ranges",
            }
        )

    if not url.startswith("http://") and not url.startswith("https://"):
        raise HTTPException(status_code=400, detail="Invalid URL protocol")

    req_headers = dict(DEFAULT_PROXY_HEADERS)
    range_header = request.headers.get("Range")
    if range_header:
        req_headers["Range"] = range_header

    # For Google Video and YouTube streams, omit proxy forwarding IP headers
    # so Google Video does not reject the signed IP matching with 403 Forbidden
    if "googlevideo.com" in url or "youtube" in url:
        req_headers.pop("X-Forwarded-For", None)
        req_headers.pop("X-Real-IP", None)
        req_headers.pop("CF-Connecting-IP", None)

    client = shared_proxy_client or httpx.AsyncClient(follow_redirects=True, timeout=30.0)
    candidates = get_candidate_stream_urls(url)

    last_error = None
    for cand_url in candidates:
        try:
            if request.method == "HEAD":
                resp = await client.head(cand_url, headers=req_headers, follow_redirects=True)
                if resp.status_code not in (200, 206, 302, 304):
                    continue
                res_headers = {}
                for key in ["content-type", "content-length", "content-range", "accept-ranges"]:
                    val = resp.headers.get(key)
                    if val:
                        res_headers[key] = val
                res_headers["accept-ranges"] = "bytes"
                res_headers["content-disposition"] = "inline"
                res_headers["access-control-allow-origin"] = "*"
                res_headers["access-control-allow-headers"] = "Range, Content-Type, Accept, Authorization"
                res_headers["access-control-expose-headers"] = "Content-Range, Content-Length, Accept-Ranges"
                if "content-type" not in res_headers or not res_headers["content-type"]:
                    res_headers["content-type"] = "audio/mpeg"
                if client is not shared_proxy_client:
                    await client.aclose()
                return Response(
                    status_code=resp.status_code,
                    headers=res_headers,
                    media_type=res_headers["content-type"],
                )

            req = client.build_request("GET", cand_url, headers=req_headers)
            resp = await client.send(req, stream=True, follow_redirects=True)

            if resp.status_code not in (200, 206, 304):
                await resp.aclose()
                continue

            res_headers = {}
            for key in ["content-type", "content-length", "content-range", "accept-ranges"]:
                val = resp.headers.get(key)
                if val:
                    res_headers[key] = val

            res_headers["accept-ranges"] = "bytes"
            res_headers["content-disposition"] = "inline"
            res_headers["access-control-allow-origin"] = "*"
            res_headers["access-control-allow-headers"] = "Range, Content-Type, Accept, Authorization"
            res_headers["access-control-expose-headers"] = "Content-Range, Content-Length, Accept-Ranges"
            if "content-type" not in res_headers or not res_headers["content-type"]:
                res_headers["content-type"] = "audio/mpeg"

            async def stream_body():
                try:
                    async for chunk in resp.aiter_bytes(chunk_size=65536):
                        yield chunk
                except Exception:
                    pass
                finally:
                    try:
                        await resp.aclose()
                    except Exception:
                        pass
                    if client is not shared_proxy_client:
                        try:
                            await client.aclose()
                        except Exception:
                            pass

            return StreamingResponse(
                stream_body(),
                status_code=resp.status_code,
                headers=res_headers,
                media_type=res_headers["content-type"],
            )
        except Exception as e:
            last_error = e
            continue

    if client is not shared_proxy_client:
        await client.aclose()
    raise HTTPException(status_code=502, detail=f"Proxy error: {str(last_error or 'Upstream failed')}")

@app.api_route("/api/proxy/http", methods=["GET", "POST", "HEAD", "OPTIONS"])
async def proxy_http(request: Request, url: str = Query(..., description="Target URL")):
    if request.method == "OPTIONS":
        return Response(
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, HEAD, OPTIONS",
                "Access-Control-Allow-Headers": "*",
            }
        )

    if not url.startswith("http://") and not url.startswith("https://"):
        raise HTTPException(status_code=400, detail="Invalid URL protocol")

    req_headers = dict(DEFAULT_PROXY_HEADERS)
    for h in ["accept", "content-type"]:
        if h in request.headers:
            req_headers[h] = request.headers[h]

    body = await request.body() if request.method == "POST" else None

    client = shared_proxy_client or httpx.AsyncClient(follow_redirects=True, timeout=25.0)
    try:
        resp = await client.request(
            method=request.method,
            url=url,
            headers=req_headers,
            content=body,
        )
        res_headers = {
            "access-control-allow-origin": "*",
            "access-control-allow-methods": "GET, POST, HEAD, OPTIONS",
            "access-control-allow-headers": "*",
        }
        if "content-type" in resp.headers:
            res_headers["content-type"] = resp.headers["content-type"]

        if client is not shared_proxy_client:
            await client.aclose()

        return Response(
            content=resp.content,
            status_code=resp.status_code,
            headers=res_headers,
            media_type=resp.headers.get("content-type"),
        )
    except Exception as e:
        if client is not shared_proxy_client:
            await client.aclose()
        raise HTTPException(status_code=502, detail=f"Proxy error: {str(e)}")
