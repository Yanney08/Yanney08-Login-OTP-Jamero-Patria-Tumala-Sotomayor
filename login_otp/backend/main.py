# 1. Imports (keep yours)
import random
import os
import hashlib
import asyncio
from typing import Dict
from datetime import datetime, timedelta

import resend
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from dotenv import load_dotenv
import aiomysql

# 2. Load environment variables FIRST
load_dotenv()

# Resend API key — read from environment
resend.api_key = os.getenv("RESEND_API_KEY")
if not resend.api_key:
    raise ValueError("RESEND_API_KEY environment variable not set")
resend_client = resend.Emails()

# MySQL config
MYSQL_CONFIG = {
    "host": os.getenv("MYSQL_HOST", "localhost"),
    "port": 3306,
    "user": os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", "1234"),
    "db": os.getenv("MYSQL_DATABASE", "logindb"),
    "charset": "utf8mb4",
    "autocommit": True,
}

# 3. Create the FastAPI app HERE — before any decorators
app = FastAPI()

# 4. Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 5. Global pool variable
pool: aiomysql.Pool = None

# 6. Startup event — NOW app exists
@app.on_event("startup")
async def startup():
    global pool
    pool = await aiomysql.create_pool(
        minsize=1,
        maxsize=10,
        **MYSQL_CONFIG
    )

    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    email VARCHAR(255) UNIQUE NOT NULL,
                    password_hash VARCHAR(128) NOT NULL,
                    created_at DATETIME NOT NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                """
            )
            await cur.execute(
                """
                CREATE TABLE IF NOT EXISTS otps (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    email VARCHAR(255) NOT NULL,
                    otp_code VARCHAR(10) NOT NULL,
                    expires_at DATETIME NOT NULL,
                    used BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at DATETIME NOT NULL,
                    INDEX(email),
                    INDEX(expires_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                """
            )

    print("MySQL connection pool created and tables ensured")

@app.on_event("shutdown")
async def shutdown():
    global pool
    if pool is not None:
        pool.close()
        await pool.wait_closed()
        print("MySQL pool closed")

# 7. Your models
class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class OTPRequest(BaseModel):
    email: EmailStr
    password: str

class VerifyRequest(BaseModel):
    email: EmailStr
    otp_code: str


def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode("utf-8")).hexdigest()


def generate_otp(length: int = 6) -> str:
    return "".join(str(random.randint(0, 9)) for _ in range(length))


async def send_otp_email(email: str, otp_code: str):
    message = f"Your login OTP code is: {otp_code}. It expires in 5 minutes."

    def send():
        return resend_client.send({
            "from": "onboarding@resend.dev",
            "to": [email],
            "subject": "Your OTP code",
            "html": f"<p>{message}</p>",
        })

    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, send)

# 8. Your routes (endpoints)
@app.get("/")
async def root():
    return {"status": "Server is running", "docs": "http://127.0.0.1:8000/docs"}

@app.post("/login")
async def login(request: LoginRequest):
    # this route validates credentials and sends OTP
    email = request.email
    password_hash = hash_password(request.password)
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT password_hash FROM users WHERE email=%s", (email,))
            row = await cur.fetchone()
            if row:
                stored_hash = row[0]
                if stored_hash != password_hash:
                    raise HTTPException(status_code=401, detail="Email or password is incorrect")
            else:
                await cur.execute(
                    "INSERT INTO users (email, password_hash, created_at) VALUES (%s, %s, %s)",
                    (email, password_hash, datetime.utcnow())
                )

            otp_code = generate_otp()
            expires_at = datetime.utcnow() + timedelta(minutes=5)

            # Try to invalidate previous OTPs for the email
            await cur.execute("UPDATE otps SET used=TRUE WHERE email=%s", (email,))

            await cur.execute(
                "INSERT INTO otps (email, otp_code, expires_at, used, created_at) VALUES (%s, %s, %s, FALSE, %s)",
                (email, otp_code, expires_at, datetime.utcnow())
            )

    try:
        await asyncio.wait_for(send_otp_email(email, otp_code), timeout=15)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="OTP email request timed out")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to send OTP email: {exc}")

    return {"message": "OTP sent", "expires_in_minutes": 5}


@app.post("/request-otp")
async def request_otp(request: OTPRequest):
    print(f"[backend] request-otp called for {request.email}")
    # alias to login logic for UI semantics
    return await login(LoginRequest(email=request.email, password=request.password))


@app.post("/verify-otp")
async def verify_otp(request: VerifyRequest):
    email = request.email
    otp_code = request.otp_code.strip()

    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, expires_at, used FROM otps WHERE email=%s AND otp_code=%s ORDER BY created_at DESC LIMIT 1",
                (email, otp_code),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=400, detail="Invalid OTP")

            otp_id, expires_at, used = row
            if used:
                raise HTTPException(status_code=400, detail="OTP already used")
            if datetime.utcnow() > expires_at:
                raise HTTPException(status_code=400, detail="OTP expired")

            await cur.execute("UPDATE otps SET used=TRUE WHERE id=%s", (otp_id,))

    return {"message": "OTP verified", "email": email}

# End of file — no code after routes that uses @app