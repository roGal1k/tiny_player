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

DB_PATH = os.environ.get("DB_PATH", "/var/lib/core_player/core_player.db")
JWT_SECRET = os.environ.get("JWT_SECRET", "core_player_super_secret_jwt_key_2026_xyz")
JWT_ALGORITHM = "HS256"

app = FastAPI(title="CorePlayer Sync Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Range", "Content-Length", "Accept-Ranges"],
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

@app.on_event("startup")
async def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
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
                playlists_json TEXT DEFAULT '[]',
                history_json TEXT DEFAULT '[]',
                settings_json TEXT DEFAULT '{}',
                updated_at INTEGER NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
        """)
        await db.commit()

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

# ----------------- Pydantic Models -----------------

class AuthRequest(BaseModel):
    username: str
    password: str

class SyncPushRequest(BaseModel):
    library: List[Dict[str, Any]] = []
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
        "INSERT INTO user_sync (user_id, library_json, playlists_json, history_json, settings_json, updated_at) VALUES (?, '[]', '[]', '[]', '{}', ?)",
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
        "SELECT library_json, playlists_json, history_json, settings_json, updated_at FROM user_sync WHERE user_id = ?",
        (user_id,),
    ) as cursor:
        row = await cursor.fetchone()
        if not row:
            return {
                "library": [],
                "playlists": [],
                "history": [],
                "settings": {},
                "updated_at": 0,
            }

        return {
            "library": json.loads(row["library_json"]),
            "playlists": json.loads(row["playlists_json"]),
            "history": json.loads(row["history_json"]),
            "settings": json.loads(row["settings_json"]),
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
        "SELECT library_json, playlists_json, history_json, settings_json, updated_at FROM user_sync WHERE user_id = ?",
        (user_id,),
    ) as cursor:
        row = await cursor.fetchone()

    server_library: List[Dict[str, Any]] = json.loads(row["library_json"]) if row else []
    server_playlists: List[Dict[str, Any]] = json.loads(row["playlists_json"]) if row else []
    server_history: List[Dict[str, Any]] = json.loads(row["history_json"]) if row else []
    server_settings: Dict[str, Any] = json.loads(row["settings_json"]) if row else {}

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

    # Merge settings (client overrides server)
    merged_settings = {**server_settings, **req.settings}

    # Save to DB
    await db.execute("""
        INSERT INTO user_sync (user_id, library_json, playlists_json, history_json, settings_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
            library_json = excluded.library_json,
            playlists_json = excluded.playlists_json,
            history_json = excluded.history_json,
            settings_json = excluded.settings_json,
            updated_at = excluded.updated_at
    """, (
        user_id,
        json.dumps(merged_library),
        json.dumps(req.playlists if req.playlists else server_playlists),
        json.dumps(req.history if req.history else server_history),
        json.dumps(merged_settings),
        now_ms,
    ))
    await db.commit()

    return {
        "status": "success",
        "library": merged_library,
        "playlists": req.playlists if req.playlists else server_playlists,
        "settings": merged_settings,
        "updated_at": now_ms,
    }

# ----------------- CORS Stream Proxy -----------------

@app.get("/api/proxy/stream")
async def proxy_stream(request: Request, url: str = Query(..., description="Target stream URL")):
    if not url.startswith("http://") and not url.startswith("https://"):
        raise HTTPException(status_code=400, detail="Invalid URL protocol")

    # Forward Range header from client if present
    range_header = request.headers.get("Range")
    req_headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    }
    if range_header:
        req_headers["Range"] = range_header

    client = httpx.AsyncClient(follow_redirects=True, timeout=30.0)
    try:
        req = client.build_request("GET", url, headers=req_headers)
        resp = await client.send(req, stream=True)

        res_headers = {}
        for key in ["content-type", "content-length", "content-range", "accept-ranges"]:
            val = resp.headers.get(key)
            if val:
                res_headers[key] = val

        res_headers["access-control-allow-origin"] = "*"
        res_headers["access-control-allow-headers"] = "Range, Content-Type, Accept"
        res_headers["access-control-expose-headers"] = "Content-Range, Content-Length, Accept-Ranges"

        async def stream_body():
            try:
                async for chunk in resp.aiter_bytes(chunk_size=65536):
                    yield chunk
            finally:
                await resp.aclose()
                await client.aclose()

        return StreamingResponse(
            stream_body(),
            status_code=resp.status_code,
            headers=res_headers,
            media_type=resp.headers.get("content-type", "audio/mpeg"),
        )
    except Exception as e:
        await client.aclose()
        raise HTTPException(status_code=502, detail=f"Proxy error: {str(e)}")
