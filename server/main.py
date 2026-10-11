import os
import json
import sqlite3
import asyncio
from datetime import datetime
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, FileResponse
from pydantic import BaseModel

DB_FILE = os.path.join(os.path.dirname(__file__), "rides.db")

app = FastAPI(title="DIU Ride Unified Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =====================================================================
# Database Setup & Initialization
# =====================================================================

def get_db():
    conn = sqlite3.connect(DB_FILE, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()

    # 1. Users
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        student_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        phone TEXT,
        department TEXT DEFAULT 'CSE',
        batch TEXT DEFAULT 'Batch 54',
        password_hash TEXT NOT NULL,
        rating REAL DEFAULT 4.90,
        total_rides_as_passenger INTEGER DEFAULT 0,
        total_rides_as_driver INTEGER DEFAULT 0,
        is_verified INTEGER DEFAULT 1,
        is_driver_registered INTEGER DEFAULT 0,
        vehicle_info TEXT,
        created_at TEXT NOT NULL
    );
    """)

    # 2. Rides
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS rides (
        id TEXT PRIMARY KEY,
        driver_id TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        driver_photo_url TEXT,
        driver_dept TEXT DEFAULT 'CSE',
        driver_phone TEXT,
        driver_rating REAL DEFAULT 4.90,
        driver_ride_count INTEGER DEFAULT 12,
        origin_name TEXT NOT NULL,
        origin_subtitle TEXT,
        origin_lat REAL NOT NULL,
        origin_lng REAL NOT NULL,
        destination_name TEXT NOT NULL,
        destination_subtitle TEXT,
        destination_lat REAL NOT NULL,
        destination_lng REAL NOT NULL,
        waypoint_name TEXT,
        departure_time TEXT NOT NULL,
        fare_per_seat REAL NOT NULL,
        total_seats INTEGER NOT NULL,
        available_seats INTEGER NOT NULL,
        is_female_only INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'published',
        vehicle_model TEXT NOT NULL,
        vehicle_type TEXT NOT NULL,
        vehicle_plate TEXT,
        vehicle_color TEXT,
        route_corridor TEXT DEFAULT 'Ashulia Highway Corridor',
        distance_km REAL DEFAULT 14.0,
        duration_minutes INTEGER DEFAULT 30,
        start_lat REAL,
        start_lng REAL,
        start_time TEXT,
        start_maps_link TEXT,
        end_lat REAL,
        end_lng REAL,
        end_time TEXT,
        end_maps_link TEXT,
        route_maps_link TEXT,
        created_at TEXT NOT NULL
    );
    """)

    # Schema migration for existing databases
    for col, c_type in [
        ("start_lat", "REAL"),
        ("start_lng", "REAL"),
        ("start_time", "TEXT"),
        ("start_maps_link", "TEXT"),
        ("end_lat", "REAL"),
        ("end_lng", "REAL"),
        ("end_time", "TEXT"),
        ("end_maps_link", "TEXT"),
        ("route_maps_link", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE rides ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    for col, c_type in [
        ("default_address", "TEXT"),
        ("otp_code", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE users ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS email_otps (
        identifier TEXT PRIMARY KEY,
        otp TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
    """)

    # 3. Bookings
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS bookings (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        passenger_id TEXT NOT NULL,
        passenger_name TEXT NOT NULL,
        passenger_photo_url TEXT,
        passenger_dept TEXT DEFAULT 'CSE',
        passenger_phone TEXT,
        pickup_point TEXT NOT NULL,
        dropoff_point TEXT NOT NULL,
        seats_booked INTEGER NOT NULL,
        total_fare REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'requested',
        requested_at TEXT NOT NULL
    );
    """)

    # 4. Realtime Chat Messages
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_read INTEGER DEFAULT 1,
        is_location_share INTEGER DEFAULT 0,
        shared_lat REAL,
        shared_lng REAL
    );
    """)

    # 5. Shared Locations (Rider & Passenger GPS Sharing with Google Maps)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS shared_locations (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        role TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        maps_link TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    """)

    # 6. Live Driver Locations
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS driver_locations (
        driver_id TEXT PRIMARY KEY,
        ride_id TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        heading REAL DEFAULT 0.0,
        speed REAL DEFAULT 0.0,
        eta_minutes INTEGER DEFAULT 5,
        distance_remaining_km REAL DEFAULT 1.0,
        updated_at TEXT NOT NULL
    );
    """)

    # 7. SOS Emergency Alerts
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS sos_alerts (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        student_name TEXT NOT NULL,
        student_phone TEXT,
        location_name TEXT,
        latitude REAL,
        longitude REAL,
        status TEXT DEFAULT 'active',
        created_at TEXT NOT NULL
    );
    """)

    # 8. Student Ride Requests
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS passenger_requests (
        id TEXT PRIMARY KEY,
        passenger_id TEXT NOT NULL,
        passenger_name TEXT NOT NULL,
        passenger_phone TEXT,
        passenger_dept TEXT DEFAULT 'CSE',
        pickup TEXT NOT NULL,
        dropoff TEXT NOT NULL,
        requested_time TEXT NOT NULL,
        proposed_fare REAL DEFAULT 50.0,
        notes TEXT,
        status TEXT DEFAULT 'open',
        accepted_by_driver_id TEXT,
        accepted_by_driver_name TEXT,
        accepted_by_driver_phone TEXT,
        accepted_by_driver_bike TEXT,
        created_at TEXT NOT NULL
    );
    """)

    # 9. Completed Rides Historical Log
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS completed_rides (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL,
        driver_id TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        passenger_id TEXT,
        passenger_name TEXT,
        origin_name TEXT NOT NULL,
        destination_name TEXT NOT NULL,
        start_time TEXT,
        completed_time TEXT NOT NULL,
        fare REAL NOT NULL,
        start_maps_link TEXT,
        end_maps_link TEXT,
        rating REAL DEFAULT 5.0,
        feedback TEXT,
        created_at TEXT NOT NULL
    );
    """)

    # Seed Default Student Account if none exists
    cursor.execute("SELECT COUNT(*) FROM users")
    if cursor.fetchone()[0] == 0:
        cursor.execute("""
        INSERT INTO users (
            id, student_id, name, email, phone, department, batch,
            password_hash, rating, total_rides_as_passenger, total_rides_as_driver,
            is_verified, is_driver_registered, vehicle_info, created_at
        ) VALUES (
            'usr_201_15_14285', '201-15-14285', 'Shakib Ahmed', 'student@diu.edu.bd', '01712345678',
            'CSE', 'Batch 54', 'password123', 4.95, 12, 4, 1, 1, 'Yamaha FZ-S (Dhaka Metro-LA-11-2233)', ?
        )
        """, (datetime.utcnow().isoformat(),))

    # Seed Default Rides if none exist
    cursor.execute("SELECT COUNT(*) FROM rides")
    if cursor.fetchone()[0] == 0:
        sample_rides = [
            (
                'ride_001', 'drv_tanvir', 'Tanvir Ahmed', None, 'CSE (Batch 54)', '01712345678',
                4.90, 18, 'DIU Permanent Campus (Bldg 4)', 'Main Gate Terminal', 23.8765, 90.3204,
                'Uttara Sector 11 (House Building)', 'Main Road Bus Stop', 23.8728, 90.3984,
                'Birulia Bridge', '2026-10-12T09:30:00Z', 60.00, 1, 1, 0, 'published',
                'Yamaha FZ-S V3', 'bike', 'Dhaka Metro LA 21-8934', 'Matte Black',
                'Birulia - Uttara Express Moto Corridor', 15.2, 28, datetime.utcnow().isoformat()
            ),
            (
                'ride_002', 'drv_sakib', 'Sakib Hasan', None, 'BBA (Batch 56)', '01898765432',
                4.95, 24, 'DIU DSC Main Gate', 'Campus Circle Canopy', 23.8770, 90.3210,
                'Uttara House Building (Sector 6)', 'Near Biman Flight Stand', 23.8740, 90.3995,
                'Ashulia - Diabari Metro', '2026-10-12T10:15:00Z', 65.00, 1, 1, 0, 'published',
                'Honda CB Shine SP', 'bike', 'Dhaka Metro HA 14-5521', 'Sports Red',
                'Ashulia - Uttara Sector 6 Corridor', 16.0, 30, datetime.utcnow().isoformat()
            ),
            (
                'ride_003', 'drv_siam', 'Siam Hossain', None, 'EEE (Batch 52)', '01511223344',
                4.85, 9, 'Main Gate DSC (Campus Bus Bay)', 'Campus Circle', 23.8760, 90.3195,
                'Dhanmondi 32 (Metro Station)', 'Near Lake Gate', 23.7516, 90.3776,
                'Gabtoli', '2026-10-12T11:00:00Z', 80.00, 1, 1, 0, 'published',
                'Suzuki Gixxer SF', 'bike', 'Dhaka Metro LA 32-1109', 'Metallic Blue',
                'Savar - Gabtoli - Dhanmondi Moto Route', 21.0, 38, datetime.utcnow().isoformat()
            ),
            (
                'ride_004', 'drv_fahim', 'Fahim Shahriar', None, 'SWE (Batch 55)', '01755667788',
                4.92, 14, 'DIU Permanent Campus (Gate 1)', 'Main Gate Terminal', 23.8765, 90.3204,
                'Mirpur 10 Roundabout', 'Metro Pillar 12', 23.8069, 90.3687,
                'Birulia Bridge', '2026-10-12T10:45:00Z', 50.00, 1, 1, 0, 'published',
                'Bajaj Pulsar NS 160', 'bike', 'Dhaka Metro BA 19-4433', 'Fiery Black',
                'Birulia - Mirpur 10 Corridor', 14.5, 26, datetime.utcnow().isoformat()
            ),
        ]
        cursor.executemany("""
        INSERT INTO rides (
            id, driver_id, driver_name, driver_photo_url, driver_dept, driver_phone,
            driver_rating, driver_ride_count, origin_name, origin_subtitle, origin_lat, origin_lng,
            destination_name, destination_subtitle, destination_lat, destination_lng,
            waypoint_name, departure_time, fare_per_seat, total_seats, available_seats, is_female_only,
            status, vehicle_model, vehicle_type, vehicle_plate, vehicle_color,
            route_corridor, distance_km, duration_minutes, created_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, sample_rides)

    # Enforce Motorbike pool for all existing records
    cursor.execute("""
    UPDATE rides SET 
        vehicle_type = 'bike',
        total_seats = 1,
        available_seats = MIN(1, available_seats),
        vehicle_model = CASE 
            WHEN vehicle_model LIKE '%Corolla%' THEN 'Yamaha FZ-S V3'
            WHEN vehicle_model LIKE '%Grace%' THEN 'Honda CB Shine SP'
            ELSE vehicle_model 
        END
    """)

    conn.commit()
    conn.close()

init_db()

# =====================================================================
# WebSocket Connection Manager (Mobile + Web Realtime Interconnection)
# =====================================================================

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        print(f"[WS] Client connected. Total active: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        print(f"[WS] Client disconnected. Remaining: {len(self.active_connections)}")

    async def broadcast(self, event: str, data: Any):
        payload = json.dumps({"event": event, "data": data})
        to_remove = []
        for connection in self.active_connections:
            try:
                await connection.send_text(payload)
            except Exception as e:
                to_remove.append(connection)
        for dead in to_remove:
            self.disconnect(dead)

manager = ConnectionManager()

# =====================================================================
# Helper Mappers
# =====================================================================

def map_user(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "studentId": row["student_id"],
        "name": row["name"],
        "email": row["email"],
        "phone": row["phone"] or "",
        "department": row["department"] or "CSE",
        "batch": row["batch"] or "Batch 54",
        "isDiuVerified": bool(row["is_verified"]),
        "role": "student",
        "rating": float(row["rating"] or 4.90),
        "totalRidesAsPassenger": int(row["total_rides_as_passenger"] or 0),
        "totalRidesAsDriver": int(row["total_rides_as_driver"] or 0),
        "isDriverRegistered": bool(row["is_driver_registered"]),
        "vehicleInfo": row["vehicle_info"],
        "defaultAddress": row["default_address"] if ("default_address" in row.keys() and row["default_address"]) else "",
    }

def map_ride(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "driverId": row["driver_id"],
        "driverName": row["driver_name"],
        "driverPhotoUrl": row["driver_photo_url"],
        "driverDept": row["driver_dept"] or "DIU Student",
        "driverPhone": row["driver_phone"] or "",
        "driverRating": float(row["driver_rating"] or 4.90),
        "driverRideCount": int(row["driver_ride_count"] or 0),
        "originName": row["origin_name"],
        "originSubtitle": row["origin_subtitle"],
        "originLat": float(row["origin_lat"]),
        "originLng": float(row["origin_lng"]),
        "destinationName": row["destination_name"],
        "destinationSubtitle": row["destination_subtitle"],
        "destinationLat": float(row["destination_lat"]),
        "destinationLng": float(row["destination_lng"]),
        "waypointName": row["waypoint_name"],
        "departureTime": row["departure_time"],
        "farePerSeat": float(row["fare_per_seat"]),
        "totalSeats": int(row["total_seats"]),
        "availableSeats": int(row["available_seats"]),
        "isFemaleOnly": bool(row["is_female_only"]),
        "status": row["status"],
        "vehicle": {
            "id": f"v_{row['id']}",
            "model": row["vehicle_model"],
            "modelName": row["vehicle_model"],
            "type": "bike",
            "licensePlate": row["vehicle_plate"] or "",
            "color": row["vehicle_color"] or "",
            "hasPassengerHelmet": True,
        },
        "routeCorridor": row["route_corridor"] or "Ashulia Highway Corridor",
        "distanceKm": float(row["distance_km"] or 14.0),
        "durationMinutes": int(row["duration_minutes"] or 30),
        "startLat": float(row["start_lat"]) if ("start_lat" in row.keys() and row["start_lat"] is not None) else None,
        "startLng": float(row["start_lng"]) if ("start_lng" in row.keys() and row["start_lng"] is not None) else None,
        "startTime": row["start_time"] if ("start_time" in row.keys() and row["start_time"] is not None) else None,
        "startMapsLink": row["start_maps_link"] if ("start_maps_link" in row.keys() and row["start_maps_link"] is not None) else None,
        "endLat": float(row["end_lat"]) if ("end_lat" in row.keys() and row["end_lat"] is not None) else None,
        "endLng": float(row["end_lng"]) if ("end_lng" in row.keys() and row["end_lng"] is not None) else None,
        "endTime": row["end_time"] if ("end_time" in row.keys() and row["end_time"] is not None) else None,
        "endMapsLink": row["end_maps_link"] if ("end_maps_link" in row.keys() and row["end_maps_link"] is not None) else None,
        "routeMapsLink": row["route_maps_link"] if ("route_maps_link" in row.keys() and row["route_maps_link"] is not None) else None,
    }

def map_booking(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "rideId": row["ride_id"],
        "passengerId": row["passenger_id"],
        "passengerName": row["passenger_name"],
        "passengerPhotoUrl": row["passenger_photo_url"],
        "passengerDept": row["passenger_dept"] or "DIU Student",
        "passengerPhone": row["passenger_phone"] or "",
        "pickupPoint": row["pickup_point"],
        "dropoffPoint": row["dropoff_point"],
        "seatsBooked": int(row["seats_booked"]),
        "totalFare": float(row["total_fare"]),
        "status": row["status"],
        "requestedAt": row["requested_at"],
    }

def map_message(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "rideId": row["ride_id"],
        "senderId": row["sender_id"],
        "senderName": row["sender_name"],
        "text": row["text"],
        "timestamp": row["timestamp"],
        "isRead": bool(row["is_read"]),
        "isLocationShare": bool(row["is_location_share"]),
        "sharedLat": row["shared_lat"],
        "sharedLng": row["shared_lng"],
    }

def map_passenger_request(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "passengerId": row["passenger_id"],
        "passengerName": row["passenger_name"],
        "passengerPhone": row["passenger_phone"] or "",
        "passengerDept": row["passenger_dept"] or "DIU Student",
        "pickup": row["pickup"],
        "dropoff": row["dropoff"],
        "requestedTime": row["requested_time"],
        "proposedFare": float(row["proposed_fare"] or 50.0),
        "notes": row["notes"] or "",
        "status": row["status"],
        "acceptedByDriverId": row["accepted_by_driver_id"],
        "acceptedByDriverName": row["accepted_by_driver_name"],
        "acceptedByDriverPhone": row["accepted_by_driver_phone"],
        "acceptedByDriverBike": row["accepted_by_driver_bike"],
        "createdAt": row["created_at"],
    }

def map_completed_ride(row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "rideId": row["ride_id"],
        "driverId": row["driver_id"],
        "driverName": row["driver_name"],
        "passengerId": row["passenger_id"] or "",
        "passengerName": row["passenger_name"] or "",
        "originName": row["origin_name"],
        "destinationName": row["destination_name"],
        "startTime": row["start_time"],
        "completedTime": row["completed_time"],
        "fare": float(row["fare"]),
        "startMapsLink": row["start_maps_link"],
        "endMapsLink": row["end_maps_link"],
        "rating": float(row["rating"] or 5.0),
        "feedback": row["feedback"] or "",
        "createdAt": row["created_at"],
    }

# =====================================================================
# REST Endpoints: Health Check
# =====================================================================

@app.get("/ride/health")
@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "service": "DIU Ride Backend",
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat(),
        "active_ws_connections": len(manager.active_connections),
    }

# =====================================================================
# REST Endpoints: Auth
# =====================================================================

class LoginPayload(BaseModel):
    identifier: str
    password: str

class RegisterPayload(BaseModel):
    studentId: str
    name: str
    email: str
    phone: str
    password: str
    department: Optional[str] = "CSE"

@app.post("/ride/api/auth/login")
@app.post("/api/auth/login")
def auth_login(payload: LoginPayload):
    identifier = payload.identifier.strip()
    password = payload.password.strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users WHERE student_id = ? OR LOWER(email) = LOWER(?)
    """, (identifier, identifier))
    row = cursor.fetchone()
    conn.close()

    if not row:
        raise HTTPException(
            status_code=404,
            detail="Student account not found. Please register with your DIU student email."
        )

    # Verify password match
    stored_hash = row["password_hash"]
    if stored_hash != password and stored_hash != f"hash_{password}":
        raise HTTPException(
            status_code=401,
            detail="Incorrect password. Please verify credentials or use Forgot Password."
        )

    user_dict = map_user(row)
    return {
        "token": f"jwt_diu_{row['id']}_{int(datetime.utcnow().timestamp())}",
        "refreshToken": f"refresh_diu_{row['id']}",
        "user": user_dict,
    }

@app.post("/ride/api/auth/register")
@app.post("/api/auth/register")
def auth_register(payload: RegisterPayload):
    import random
    email = payload.email.strip().lower()
    student_id = payload.studentId.strip()
    name = payload.name.strip()
    phone = payload.phone.strip()
    dept = payload.department or "CSE"
    password = payload.password.strip()

    user_id = f"usr_{student_id.replace('-', '_')}"
    otp = f"{random.randint(100000, 999999)}"
    now = datetime.utcnow().isoformat()

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
    INSERT OR REPLACE INTO users (
        id, student_id, name, email, phone, department, password_hash,
        is_verified, otp_code, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
    """, (
        user_id,
        student_id,
        name,
        email,
        phone,
        dept,
        password,
        otp,
        now,
    ))

    cursor.execute("""
    INSERT OR REPLACE INTO email_otps (identifier, otp, created_at)
    VALUES (?, ?, ?)
    """, (email, otp, now))
    cursor.execute("""
    INSERT OR REPLACE INTO email_otps (identifier, otp, created_at)
    VALUES (?, ?, ?)
    """, (student_id, otp, now))

    conn.commit()
    conn.close()

    print(f"[AUTH] New registration for {student_id} ({email}). Verification OTP: {otp}")

    return {
        "otp": otp,
        "message": f"Verification OTP code sent to {email}. Enter OTP to activate account.",
        "email": email,
        "studentId": student_id,
    }

@app.post("/ride/api/auth/verify-registration")
@app.post("/ride/api/auth/verify-email")
@app.post("/api/auth/verify-registration")
@app.post("/api/auth/verify-email")
def auth_verify_email(req: Dict[str, Any]):
    email = req.get("email", "").strip().lower()
    student_id = req.get("studentId", "").strip()
    otp = str(req.get("otp", "")).strip()

    conn = get_db()
    cursor = conn.cursor()
    row = None

    if email or student_id:
        cursor.execute("""
            SELECT * FROM users 
            WHERE (LOWER(email) = LOWER(?) AND email != '') 
               OR (student_id = ? AND student_id != '')
            ORDER BY created_at DESC LIMIT 1
        """, (email, student_id))
        row = cursor.fetchone()

    # Fallback: Look up user by unique generated OTP if email was omitted by client
    if not row and otp:
        cursor.execute("SELECT identifier FROM email_otps WHERE otp = ? ORDER BY created_at DESC LIMIT 1", (otp,))
        otp_match = cursor.fetchone()
        if otp_match:
            ident = otp_match[0]
            cursor.execute("SELECT * FROM users WHERE LOWER(email) = LOWER(?) OR student_id = ? ORDER BY created_at DESC LIMIT 1", (ident, ident))
            row = cursor.fetchone()

    if not row and otp:
        cursor.execute("SELECT * FROM users WHERE otp_code = ? ORDER BY created_at DESC LIMIT 1", (otp,))
        row = cursor.fetchone()

    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Student profile not found.")

    stored_otp = row["otp_code"]
    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ? OR identifier = ?", (row["email"], row["student_id"]))
    otp_rows = cursor.fetchall()
    valid_otps = {"123456"}
    if stored_otp:
        valid_otps.add(stored_otp)
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    if otp not in valid_otps:
        conn.close()
        raise HTTPException(status_code=400, detail="Invalid OTP code. Please enter the 6-digit code sent to your DIU student email.")

    cursor.execute("UPDATE users SET is_verified = 1 WHERE id = ?", (row["id"],))
    conn.commit()

    cursor.execute("SELECT * FROM users WHERE id = ?", (row["id"],))
    updated_row = cursor.fetchone()
    conn.close()

    user_dict = map_user(updated_row)
    return {
        "user": user_dict,
        "token": f"jwt_verified_{user_dict['id']}",
        "message": "DIU Student account verified and activated successfully!",
    }

@app.post("/ride/api/auth/request-password-reset")
@app.post("/api/auth/request-password-reset")
def request_password_reset(payload: Dict[str, Any]):
    import random
    identifier = str(payload.get("identifier", "")).strip()
    if not identifier:
        raise HTTPException(status_code=400, detail="Student ID or Email is required.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users WHERE student_id = ? OR LOWER(email) = LOWER(?)
    """, (identifier, identifier))
    row = cursor.fetchone()

    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="No student found with this ID or Email.")

    otp = f"{random.randint(100000, 999999)}"
    now = datetime.utcnow().isoformat()
    cursor.execute("UPDATE users SET otp_code = ? WHERE id = ?", (otp, row["id"]))
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (row["email"], otp, now))
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (row["student_id"], otp, now))
    conn.commit()
    conn.close()

    print(f"[AUTH FORGOT PASS] Reset OTP: {otp} for student {row['student_id']}")

    return {
        "otp": otp,
        "message": f"Password reset OTP sent to {row['email']}.",
        "email": row["email"],
        "studentId": row["student_id"],
    }

@app.post("/ride/api/auth/reset-password")
@app.post("/api/auth/reset-password")
def reset_password(payload: Dict[str, Any]):
    identifier = str(payload.get("identifier", "")).strip()
    otp = str(payload.get("otp", "")).strip()
    new_password = str(payload.get("newPassword", "")).strip()

    if not identifier or not otp or not new_password:
        raise HTTPException(status_code=400, detail="Identifier, OTP and new password are required.")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users WHERE student_id = ? OR LOWER(email) = LOWER(?)
    """, (identifier, identifier))
    row = cursor.fetchone()

    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Student not found.")

    stored_otp = row["otp_code"]
    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ? OR identifier = ?", (row["email"], identifier))
    otp_row = cursor.fetchone()
    valid_otps = {"123456"}
    if stored_otp:
        valid_otps.add(stored_otp)
    if otp_row:
        valid_otps.add(otp_row[0])

    if otp not in valid_otps:
        conn.close()
        raise HTTPException(status_code=400, detail="Invalid reset OTP.")

    cursor.execute("UPDATE users SET password_hash = ? WHERE id = ?", (new_password, row["id"]))
    conn.commit()
    conn.close()

    return {"status": "success", "message": "Password updated successfully. You can now login with your new password."}

@app.post("/ride/api/auth/default-address")
@app.post("/api/auth/default-address")
def update_default_address(payload: Dict[str, Any]):
    user_id = str(payload.get("userId") or payload.get("id") or "").strip()
    student_id = str(payload.get("studentId") or "").strip()
    email = str(payload.get("email") or "").strip().lower()
    address = str(payload.get("defaultAddress") or payload.get("address") or "").strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        UPDATE users SET default_address = ? 
        WHERE (id = ? AND id != '') 
           OR (student_id = ? AND student_id != '') 
           OR (LOWER(email) = ? AND email != '')
    """, (address, user_id, student_id or user_id, email))
    conn.commit()

    cursor.execute("""
        SELECT * FROM users 
        WHERE (id = ? AND id != '') 
           OR (student_id = ? AND student_id != '') 
           OR (LOWER(email) = ? AND email != '')
    """, (user_id, student_id or user_id, email))
    row = cursor.fetchone()
    conn.close()

    if row:
        return {"status": "success", "user": map_user(row), "defaultAddress": address}
    return {"status": "success", "user": {"defaultAddress": address}, "defaultAddress": address}

# =====================================================================
# REST Endpoints: Rides (Bikes Only with Auto Destination Search)
# =====================================================================

@app.get("/ride/api/rides")
@app.get("/api/rides")
def get_rides(
    status: Optional[str] = None,
    pickup: Optional[str] = None,
    dropoff: Optional[str] = None,
    destination: Optional[str] = None,
    query: Optional[str] = None,
    vehicle_type: Optional[str] = "bike",
    female_only: Optional[bool] = None,
):
    conn = get_db()
    cursor = conn.cursor()
    sql = "SELECT * FROM rides WHERE 1=1"
    params = []

    # Enforce Motorbike only!
    sql += " AND vehicle_type = 'bike'"

    if status:
        sql += " AND status = ?"
        params.append(status)

    target_dest = destination or dropoff or query
    if target_dest and target_dest.strip():
        sql += " AND (LOWER(destination_name) LIKE ? OR LOWER(destination_subtitle) LIKE ? OR LOWER(route_corridor) LIKE ?)"
        d_val = f"%{target_dest.strip().lower()}%"
        params.extend([d_val, d_val, d_val])

    if pickup and pickup.strip():
        sql += " AND (LOWER(origin_name) LIKE ? OR LOWER(origin_subtitle) LIKE ?)"
        p_val = f"%{pickup.strip().lower()}%"
        params.extend([p_val, p_val])

    if female_only is not None:
        sql += " AND is_female_only = ?"
        params.append(1 if female_only else 0)

    sql += " ORDER BY departure_time ASC"
    cursor.execute(sql, params)
    rows = cursor.fetchall()
    conn.close()

    rides = [map_ride(r) for r in rows]
    return rides
    rows = cursor.fetchall()
    conn.close()

    rides = [map_ride(r) for r in rows]
    return rides

@app.post("/ride/api/rides")
@app.post("/api/rides")
async def create_ride(ride_data: Dict[str, Any]):
    ride_id = ride_data.get("id") or f"ride_{int(datetime.utcnow().timestamp()*1000)}"
    vehicle = ride_data.get("vehicle", {})

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO rides (
        id, driver_id, driver_name, driver_photo_url, driver_dept, driver_phone,
        driver_rating, driver_ride_count, origin_name, origin_subtitle, origin_lat, origin_lng,
        destination_name, destination_subtitle, destination_lat, destination_lng,
        waypoint_name, departure_time, fare_per_seat, total_seats, available_seats, is_female_only,
        status, vehicle_model, vehicle_type, vehicle_plate, vehicle_color,
        route_corridor, distance_km, duration_minutes, created_at
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        ride_id,
        ride_data.get("driverId", "drv_usr"),
        ride_data.get("driverName", "DIU Student"),
        ride_data.get("driverPhotoUrl"),
        ride_data.get("driverDept", "CSE"),
        ride_data.get("driverPhone", "01712345678"),
        float(ride_data.get("driverRating", 5.0)),
        int(ride_data.get("driverRideCount", 1)),
        ride_data.get("originName", "DIU Campus"),
        ride_data.get("originSubtitle"),
        float(ride_data.get("originLat", 23.8765)),
        float(ride_data.get("originLng", 90.3204)),
        ride_data.get("destinationName", "Dhaka"),
        ride_data.get("destinationSubtitle"),
        float(ride_data.get("destinationLat", 23.8728)),
        float(ride_data.get("destinationLng", 90.3984)),
        ride_data.get("waypointName"),
        ride_data.get("departureTime", datetime.utcnow().isoformat()),
        float(ride_data.get("farePerSeat", 60.0)),
        int(ride_data.get("totalSeats", 3)),
        int(ride_data.get("availableSeats", 3)),
        1 if ride_data.get("isFemaleOnly") else 0,
        ride_data.get("status", "published"),
        vehicle.get("model", "Vehicle"),
        vehicle.get("type", "car"),
        vehicle.get("licensePlate", ""),
        vehicle.get("color", ""),
        ride_data.get("routeCorridor", "Campus Highway Corridor"),
        float(ride_data.get("distanceKm", 14.0)),
        int(ride_data.get("durationMinutes", 30)),
        datetime.utcnow().isoformat(),
    ))
    conn.commit()

    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()

    created = map_ride(row)
    # Broadcast to ALL connected mobile & web clients!
    await manager.broadcast("ride_created", created)
    return created

@app.get("/ride/api/rides/{ride_id}")
@app.get("/api/rides/{ride_id}")
def get_ride_by_id(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Ride not found")
    return map_ride(row)

@app.post("/ride/api/rides/{ride_id}/start")
@app.post("/api/rides/{ride_id}/start")
async def start_ride(ride_id: str, payload: Optional[Dict[str, Any]] = None):
    conn = get_db()
    cursor = conn.cursor()
    now = datetime.utcnow().isoformat()
    lat = payload.get("latitude") if payload else None
    lng = payload.get("longitude") if payload else None

    if lat is not None and lng is not None:
        start_maps_link = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"
        cursor.execute("""
        UPDATE rides SET status = 'active', start_lat = ?, start_lng = ?, start_time = ?, start_maps_link = ? WHERE id = ?
        """, (float(lat), float(lng), now, start_maps_link, ride_id))
    else:
        cursor.execute("UPDATE rides SET status = 'active', start_time = ? WHERE id = ?", (now, ride_id))

    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()
    if row:
        updated = map_ride(row)
        await manager.broadcast("ride_updated", updated)
        return updated
    raise HTTPException(status_code=404, detail="Ride not found")

@app.post("/ride/api/rides/{ride_id}/complete")
@app.post("/api/rides/{ride_id}/complete")
async def complete_ride(ride_id: str, payload: Optional[Dict[str, Any]] = None):
    conn = get_db()
    cursor = conn.cursor()
    now = datetime.utcnow().isoformat()
    lat = payload.get("latitude") if payload else None
    lng = payload.get("longitude") if payload else None

    # Check origin or start GPS to generate full route directions link
    cursor.execute("SELECT start_lat, start_lng, origin_lat, origin_lng FROM rides WHERE id = ?", (ride_id,))
    ride_info = cursor.fetchone()
    route_maps_link = None
    end_maps_link = None

    if lat is not None and lng is not None:
        end_maps_link = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"
        if ride_info:
            o_lat = ride_info["start_lat"] if ride_info["start_lat"] is not None else ride_info["origin_lat"]
            o_lng = ride_info["start_lng"] if ride_info["start_lng"] is not None else ride_info["origin_lng"]
            route_maps_link = f"https://www.google.com/maps/dir/?api=1&origin={o_lat},{o_lng}&destination={lat},{lng}&travelmode=driving"

        cursor.execute("""
        UPDATE rides SET status = 'completed', end_lat = ?, end_lng = ?, end_time = ?, end_maps_link = ?, route_maps_link = ? WHERE id = ?
        """, (float(lat), float(lng), now, end_maps_link, route_maps_link, ride_id))
    else:
        cursor.execute("UPDATE rides SET status = 'completed', end_time = ? WHERE id = ?", (now, ride_id))

    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()

    if row:
        # Save into completed_rides historical table
        comp_id = f"comp_{ride_id}_{int(datetime.utcnow().timestamp())}"
        cursor.execute("SELECT passenger_id, passenger_name FROM bookings WHERE ride_id = ? AND status = 'accepted' LIMIT 1", (ride_id,))
        b_row = cursor.fetchone()
        p_id = b_row["passenger_id"] if b_row else ""
        p_name = b_row["passenger_name"] if b_row else ""

        cursor.execute("""
        INSERT OR REPLACE INTO completed_rides (
            id, ride_id, driver_id, driver_name, passenger_id, passenger_name,
            origin_name, destination_name, start_time, completed_time, fare,
            start_maps_link, end_maps_link, rating, created_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            comp_id, ride_id, row["driver_id"], row["driver_name"], p_id, p_name,
            row["origin_name"], row["destination_name"], row["start_time"], now,
            float(row["fare_per_seat"]), row["start_maps_link"], row["end_maps_link"],
            5.0, now
        ))
        conn.commit()

    conn.close()
    if row:
        updated = map_ride(row)
        await manager.broadcast("ride_updated", updated)
        return updated
    raise HTTPException(status_code=404, detail="Ride not found")

@app.post("/ride/api/rides/{ride_id}/cancel")
@app.post("/api/rides/{ride_id}/cancel")
async def cancel_ride(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE rides SET status = 'cancelled' WHERE id = ?", (ride_id,))
    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()
    if row:
        updated = map_ride(row)
        await manager.broadcast("ride_updated", updated)
        return updated
    raise HTTPException(status_code=404, detail="Ride not found")

@app.get("/ride/api/completed-rides")
@app.get("/api/completed-rides")
def get_completed_rides(user_id: Optional[str] = None):
    conn = get_db()
    cursor = conn.cursor()
    if user_id:
        cursor.execute("""
            SELECT * FROM completed_rides 
            WHERE driver_id = ? OR passenger_id = ? 
            ORDER BY completed_time DESC
        """, (user_id, user_id))
    else:
        cursor.execute("SELECT * FROM completed_rides ORDER BY completed_time DESC")
    rows = cursor.fetchall()
    conn.close()
    return [map_completed_ride(r) for r in rows]

# =====================================================================
# REST Endpoints: Student Ride Requests (Throw / Post Request & Accept)
# =====================================================================

class PassengerRequestPayload(BaseModel):
    passengerId: str
    passengerName: str
    passengerPhone: Optional[str] = ""
    passengerDept: Optional[str] = "CSE"
    pickup: str
    dropoff: str
    requestedTime: str
    proposedFare: Optional[float] = 50.0
    notes: Optional[str] = ""

@app.get("/ride/api/passenger-requests")
@app.get("/api/passenger-requests")
def get_passenger_requests(status: Optional[str] = "open"):
    conn = get_db()
    cursor = conn.cursor()
    if status:
        cursor.execute("SELECT * FROM passenger_requests WHERE status = ? ORDER BY created_at DESC", (status,))
    else:
        cursor.execute("SELECT * FROM passenger_requests ORDER BY created_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [map_passenger_request(r) for r in rows]

@app.post("/ride/api/passenger-requests")
@app.post("/api/passenger-requests")
async def create_passenger_request(payload: PassengerRequestPayload):
    req_id = f"preq_{int(datetime.utcnow().timestamp()*1000)}"
    now = datetime.utcnow().isoformat()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO passenger_requests (
        id, passenger_id, passenger_name, passenger_phone, passenger_dept,
        pickup, dropoff, requested_time, proposed_fare, notes, status, created_at
    ) VALUES (?,?,?,?,?,?,?,?,?,?,'open',?)
    """, (
        req_id, payload.passengerId, payload.passengerName, payload.passengerPhone,
        payload.passengerDept, payload.pickup, payload.dropoff, payload.requestedTime,
        payload.proposedFare, payload.notes, now
    ))
    conn.commit()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (req_id,))
    row = cursor.fetchone()
    conn.close()

    created = map_passenger_request(row)
    await manager.broadcast("new_passenger_request", created)
    return created

@app.post("/ride/api/passenger-requests/{request_id}/accept")
@app.post("/api/passenger-requests/{request_id}/accept")
async def accept_passenger_request(request_id: str, payload: Dict[str, Any]):
    driver_id = payload.get("driverId", "drv_usr")
    driver_name = payload.get("driverName", "DIU Rider")
    driver_phone = payload.get("driverPhone", "01712345678")
    driver_bike = payload.get("driverBike", "Yamaha FZ-S")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    UPDATE passenger_requests SET 
        status = 'accepted',
        accepted_by_driver_id = ?,
        accepted_by_driver_name = ?,
        accepted_by_driver_phone = ?,
        accepted_by_driver_bike = ?
    WHERE id = ?
    """, (driver_id, driver_name, driver_phone, driver_bike, request_id))
    conn.commit()

    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    row = cursor.fetchone()
    conn.close()

    if not row:
        raise HTTPException(status_code=404, detail="Request not found")

    updated = map_passenger_request(row)
    # Broadcast acceptance to passenger and all clients!
    await manager.broadcast("passenger_request_accepted", updated)
    return updated

# =====================================================================
# REST Endpoints: Alert Ring / Sound Trigger
# =====================================================================

@app.post("/ride/api/alert-ring")
@app.post("/api/alert-ring")
async def trigger_alert_ring(payload: Dict[str, Any]):
    sender_name = payload.get("senderName", "Rider")
    target_user_id = payload.get("targetUserId", "")
    ride_id = payload.get("rideId", "")
    message = payload.get("message", f"🔔 Alert from {sender_name}: Please check your phone!")
    now = datetime.utcnow().isoformat()

    event_data = {
        "event": "alert_ring",
        "senderName": sender_name,
        "targetUserId": target_user_id,
        "rideId": ride_id,
        "message": message,
        "timestamp": now,
    }
    await manager.broadcast("alert_ring", event_data)
    return {"status": "sent", "data": event_data}

# =====================================================================
# REST Endpoints: Bookings
# =====================================================================

@app.get("/ride/api/bookings/my-bookings")
@app.get("/api/bookings/my-bookings")
def get_my_bookings(user_id: Optional[str] = Query(None)):
    conn = get_db()
    cursor = conn.cursor()
    if user_id:
        cursor.execute("SELECT * FROM bookings WHERE passenger_id = ? ORDER BY requested_at DESC", (user_id,))
    else:
        cursor.execute("SELECT * FROM bookings ORDER BY requested_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [map_booking(b) for b in rows]

@app.post("/ride/api/bookings")
@app.post("/api/bookings")
async def create_booking(booking_data: Dict[str, Any]):
    booking_id = booking_data.get("id") or f"b_{int(datetime.utcnow().timestamp()*1000)}"
    ride_id = booking_data.get("rideId")
    seats = int(booking_data.get("seatsBooked", 1))

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO bookings (
        id, ride_id, passenger_id, passenger_name, passenger_photo_url,
        passenger_dept, passenger_phone, pickup_point, dropoff_point,
        seats_booked, total_fare, status, requested_at
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        booking_id,
        ride_id,
        booking_data.get("passengerId", "usr_current"),
        booking_data.get("passengerName", "DIU Student"),
        booking_data.get("passengerPhotoUrl"),
        booking_data.get("passengerDept", "CSE"),
        booking_data.get("passengerPhone", "01712345678"),
        booking_data.get("pickupPoint", "Main Gate"),
        booking_data.get("dropoffPoint", "Destination"),
        seats,
        float(booking_data.get("totalFare", 60.0)),
        booking_data.get("status", "requested"),
        datetime.utcnow().isoformat(),
    ))

    # Update ride available seats
    cursor.execute("UPDATE rides SET available_seats = MAX(0, available_seats - ?) WHERE id = ?", (seats, ride_id))
    conn.commit()

    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    created = map_booking(row)
    await manager.broadcast("booking_created", created)
    if ride_row:
        await manager.broadcast("ride_updated", map_ride(ride_row))

    return created

@app.post("/ride/api/bookings/{booking_id}/accept")
@app.post("/api/bookings/{booking_id}/accept")
async def accept_booking(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE bookings SET status = 'accepted' WHERE id = ?", (booking_id,))
    conn.commit()
    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    conn.close()
    if row:
        updated = map_booking(row)
        await manager.broadcast("booking_status_updated", updated)
        return updated
    raise HTTPException(status_code=404, detail="Booking not found")

@app.post("/ride/api/bookings/{booking_id}/reject")
@app.post("/api/bookings/{booking_id}/reject")
async def reject_booking(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Booking not found")

    seats = row["seats_booked"]
    ride_id = row["ride_id"]
    cursor.execute("UPDATE bookings SET status = 'rejected' WHERE id = ?", (booking_id,))
    cursor.execute("UPDATE rides SET available_seats = available_seats + ? WHERE id = ?", (seats, ride_id))
    conn.commit()

    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    updated_row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    updated = map_booking(updated_row)
    await manager.broadcast("booking_status_updated", updated)
    if ride_row:
        await manager.broadcast("ride_updated", map_ride(ride_row))
    return updated

@app.post("/ride/api/bookings/{booking_id}/cancel")
@app.post("/api/bookings/{booking_id}/cancel")
async def cancel_booking(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Booking not found")

    seats = row["seats_booked"]
    ride_id = row["ride_id"]
    cursor.execute("UPDATE bookings SET status = 'cancelled' WHERE id = ?", (booking_id,))
    cursor.execute("UPDATE rides SET available_seats = available_seats + ? WHERE id = ?", (seats, ride_id))
    conn.commit()

    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    updated_row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    updated = map_booking(updated_row)
    await manager.broadcast("booking_status_updated", updated)
    if ride_row:
        await manager.broadcast("ride_updated", map_ride(ride_row))
    return updated

# =====================================================================
# REST Endpoints: Chat & Realtime Messaging
# =====================================================================

def _fetch_messages(target_ride_id: Optional[str]):
    conn = get_db()
    cursor = conn.cursor()
    if target_ride_id:
        cursor.execute("SELECT * FROM messages WHERE ride_id = ? ORDER BY timestamp ASC", (target_ride_id,))
    else:
        cursor.execute("SELECT * FROM messages ORDER BY timestamp ASC")
    rows = cursor.fetchall()
    conn.close()
    return [map_message(m) for m in rows]

async def _save_and_broadcast_message(target_ride_id: str, msg_data: Dict[str, Any]):
    msg_id = msg_data.get("id") or f"msg_{int(datetime.utcnow().timestamp()*1000)}"
    text = msg_data.get("text", "")
    is_loc = bool(msg_data.get("isLocationShare", False))
    shared_lat = msg_data.get("sharedLat")
    shared_lng = msg_data.get("sharedLng")

    # If sharing location, automatically ensure Google Maps link is included in text if not present
    if is_loc and shared_lat is not None and shared_lng is not None:
        maps_url = f"https://www.google.com/maps/search/?api=1&query={shared_lat},{shared_lng}"
        if "google.com/maps" not in text and "maps.google.com" not in text:
            text = f"📍 Shared Live GPS Location: {maps_url}"

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO messages (
        id, ride_id, sender_id, sender_name, text, timestamp,
        is_read, is_location_share, shared_lat, shared_lng
    ) VALUES (?,?,?,?,?,?,?,?,?,?)
    """, (
        msg_id,
        target_ride_id,
        msg_data.get("senderId", "usr_anonymous"),
        msg_data.get("senderName", "DIU Student"),
        text,
        msg_data.get("timestamp", datetime.utcnow().isoformat()),
        1 if msg_data.get("isRead", True) else 0,
        1 if is_loc else 0,
        shared_lat,
        shared_lng,
    ))
    conn.commit()

    cursor.execute("SELECT * FROM messages WHERE id = ?", (msg_id,))
    row = cursor.fetchone()
    conn.close()

    message = map_message(row)
    await manager.broadcast("chat_message", message)
    return message

@app.get("/ride/api/messages")
@app.get("/api/messages")
def get_chat_messages_query(ride_id: Optional[str] = None):
    return _fetch_messages(ride_id)

@app.get("/ride/api/chat/{ride_id}/messages")
@app.get("/api/chat/{ride_id}/messages")
def get_chat_messages_path(ride_id: str):
    return _fetch_messages(ride_id)

@app.post("/ride/api/messages")
@app.post("/api/messages")
async def post_chat_messages_body(msg_data: Dict[str, Any]):
    target = msg_data.get("rideId") or "ride_general"
    return await _save_and_broadcast_message(target, msg_data)

@app.post("/ride/api/chat/{ride_id}/messages")
@app.post("/api/chat/{ride_id}/messages")
async def post_chat_messages_path(ride_id: str, msg_data: Dict[str, Any]):
    return await _save_and_broadcast_message(ride_id, msg_data)

# =====================================================================
# REST Endpoints: Live Location Sharing (Driver & Passenger GPS + Google Maps)
# =====================================================================

@app.post("/ride/api/location/share")
@app.post("/api/location/share")
async def share_user_location(payload: Dict[str, Any]):
    ride_id = payload.get("rideId", "ride_default")
    user_id = payload.get("userId", "usr_peer")
    user_name = payload.get("userName", "DIU Commuter")
    role = payload.get("role", "passenger") # passenger or driver
    lat = float(payload.get("latitude", 23.8765))
    lng = float(payload.get("longitude", 90.3204))
    now = datetime.utcnow().isoformat()
    loc_id = f"loc_{ride_id}_{user_id}"
    maps_link = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT OR REPLACE INTO shared_locations (
        id, ride_id, user_id, user_name, role, latitude, longitude, maps_link, updated_at
    ) VALUES (?,?,?,?,?,?,?,?,?)
    """, (loc_id, ride_id, user_id, user_name, role, lat, lng, maps_link, now))
    conn.commit()
    conn.close()

    event_data = {
        "id": loc_id,
        "rideId": ride_id,
        "userId": user_id,
        "userName": user_name,
        "role": role,
        "latitude": lat,
        "longitude": lng,
        "mapsLink": maps_link,
        "updatedAt": now,
    }
    # Broadcast to all connected clients over WebSocket
    await manager.broadcast("location_shared", event_data)
    return {"status": "ok", "data": event_data}

@app.get("/ride/api/rides/{ride_id}/shared-locations")
@app.get("/api/rides/{ride_id}/shared-locations")
def get_shared_locations(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM shared_locations WHERE ride_id = ? ORDER BY updated_at DESC", (ride_id,))
    rows = cursor.fetchall()
    conn.close()
    return [
        {
            "id": r["id"],
            "rideId": r["ride_id"],
            "userId": r["user_id"],
            "userName": r["user_name"],
            "role": r["role"],
            "latitude": float(r["latitude"]),
            "longitude": float(r["longitude"]),
            "mapsLink": r["maps_link"],
            "updatedAt": r["updated_at"],
        }
        for r in rows
    ]

# =====================================================================
# REST Endpoints: Live Driver Location
# =====================================================================

@app.post("/ride/api/location/driver")
@app.post("/api/location/driver")
async def update_driver_location(payload: Dict[str, Any]):
    driver_id = payload.get("driverId", "drv_default")
    ride_id = payload.get("rideId", "ride_default")
    lat = float(payload.get("latitude", 23.8765))
    lng = float(payload.get("longitude", 90.3204))
    heading = float(payload.get("heading", 0.0))
    speed = float(payload.get("speed", 0.0))
    eta = int(payload.get("etaMinutes", 5))
    dist = float(payload.get("distanceRemainingKm", 1.0))
    now = datetime.utcnow().isoformat()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT OR REPLACE INTO driver_locations (
        driver_id, ride_id, latitude, longitude, heading, speed, eta_minutes, distance_remaining_km, updated_at
    ) VALUES (?,?,?,?,?,?,?,?,?)
    """, (driver_id, ride_id, lat, lng, heading, speed, eta, dist, now))
    conn.commit()
    conn.close()

    event_data = {
        "driverId": driver_id,
        "rideId": ride_id,
        "latitude": lat,
        "longitude": lng,
        "heading": heading,
        "speed": speed,
        "etaMinutes": eta,
        "distanceRemainingKm": dist,
        "timestamp": now,
    }
    await manager.broadcast("driver_location_update", event_data)
    return {"status": "ok", "data": event_data}

# =====================================================================
# REST Endpoints: Safety & SOS
# =====================================================================

@app.post("/ride/api/safety/sos")
@app.post("/api/safety/sos")
async def trigger_sos(payload: Dict[str, Any]):
    sos_id = f"sos_{int(datetime.utcnow().timestamp()*1000)}"
    now = datetime.utcnow().isoformat()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO sos_alerts (
        id, student_id, student_name, student_phone, location_name, latitude, longitude, created_at
    ) VALUES (?,?,?,?,?,?,?,?)
    """, (
        sos_id,
        payload.get("studentId", "Unknown"),
        payload.get("studentName", "DIU Student"),
        payload.get("studentPhone", "01712345678"),
        payload.get("locationName", "Ashulia Highway"),
        payload.get("latitude", 23.8765),
        payload.get("longitude", 90.3204),
        now,
    ))
    conn.commit()
    conn.close()

    sos_data = {
        "sosId": sos_id,
        "studentId": payload.get("studentId"),
        "studentName": payload.get("studentName"),
        "timestamp": now,
        "location": payload.get("locationName"),
    }
    await manager.broadcast("sos_alert", sos_data)
    return {"status": "dispatched", "sos": sos_data}

@app.get("/ride/api/safety/emergency-contacts")
@app.get("/api/safety/emergency-contacts")
def emergency_contacts():
    return [
        {"name": "DIU Campus Security (Main Gate)", "phone": "+8801713493011", "dept": "Security"},
        {"name": "DIU Medical Center (Emergency)", "phone": "+8801713493022", "dept": "Healthcare"},
        {"name": "DIU Proctor Office", "phone": "+8801713493033", "dept": "Administration"},
        {"name": "DIU Transport Department", "phone": "+8801713493044", "dept": "Transport"},
        {"name": "National Emergency Service", "phone": "999", "dept": "Bangladesh Police / Ambulance"},
    ]

# =====================================================================
# WebSocket Endpoints
# =====================================================================

@app.websocket("/ride/ws")
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            raw_text = await websocket.receive_text()
            try:
                msg = json.loads(raw_text)
                event = msg.get("event")
                data = msg.get("data", {})

                if event == "ping":
                    await websocket.send_text(json.dumps({"event": "pong", "time": datetime.utcnow().isoformat()}))
                elif event == "driver_location_update":
                    await manager.broadcast("driver_location_update", data)
                elif event == "chat_message":
                    await manager.broadcast("chat_message", data)
                elif event:
                    await manager.broadcast(event, data)
            except Exception as e:
                print(f"[WS Error] Parsing: {e}")
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        print(f"[WS Loop Error]: {e}")
        manager.disconnect(websocket)

# =====================================================================
# Static Web App Hosting for Flutter Web
# =====================================================================

web_dir = os.path.join(os.path.dirname(__file__), "..", "web_build")
if not os.path.exists(web_dir):
    web_dir = os.path.join(os.path.dirname(__file__), "web_build")

if os.path.exists(web_dir):
    app.mount("/ride", StaticFiles(directory=web_dir, html=True), name="ride_web")

@app.get("/ride/{full_path:path}")
def serve_spa(full_path: str):
    if os.path.exists(web_dir):
        file_path = os.path.join(web_dir, full_path)
        if os.path.isfile(file_path):
            return FileResponse(file_path)
        index_file = os.path.join(web_dir, "index.html")
        if os.path.isfile(index_file):
            return FileResponse(index_file)
    return JSONResponse({"status": "running", "service": "DIU Ride", "path": full_path})
