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

    # 5. Live Driver Locations
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

    # 6. SOS Emergency Alerts
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
                'Birulia Bridge', '2026-10-12T09:30:00Z', 70.00, 4, 3, 0, 'published',
                'Toyota Corolla Axio', 'car', 'Dhaka Metro GA 21-8934', 'Silver',
                'Birulia - Uttara Express Corridor', 15.2, 32, datetime.utcnow().isoformat()
            ),
            (
                'ride_002', 'drv_nusrat', 'Nusrat Jahan', None, 'BBA (Batch 49)', '01898765432',
                4.95, 24, 'DIU Girls Hostel (DSC)', 'Campus Gate 2', 23.8770, 90.3210,
                'Mirpur 10 Roundabout', 'Metro Pillar 12', 23.8069, 90.3687,
                'Ashulia Highway', '2026-10-12T10:15:00Z', 85.00, 3, 2, 1, 'published',
                'Honda Grace Hybrid', 'car', 'Dhaka Metro KHA 14-5521', 'Pearl White',
                'Ashulia - Mirpur Corridor (Female Only)', 18.5, 38, datetime.utcnow().isoformat()
            ),
            (
                'ride_003', 'drv_siam', 'Siam Hossain', None, 'EEE (Batch 52)', '01511223344',
                4.85, 9, 'Main Gate DSC (Campus Bus Bay)', 'Campus Circle', 23.8760, 90.3195,
                'Dhanmondi 32 (Metro Station)', 'Near Lake Gate', 23.7516, 90.3776,
                'Gabtoli', '2026-10-12T11:00:00Z', 95.00, 1, 1, 0, 'published',
                'Yamaha FZ-S V3', 'bike', 'Dhaka Metro LA 32-1109', 'Matte Black',
                'Savar - Gabtoli - Dhanmondi Route', 21.0, 40, datetime.utcnow().isoformat()
            )
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
            "model": row["vehicle_model"],
            "type": row["vehicle_type"],
            "licensePlate": row["vehicle_plate"] or "",
            "color": row["vehicle_color"] or "",
        },
        "routeCorridor": row["route_corridor"] or "Ashulia Highway Corridor",
        "distanceKm": float(row["distance_km"] or 14.0),
        "durationMinutes": int(row["duration_minutes"] or 30),
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
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users WHERE student_id = ? OR email = ?
    """, (payload.identifier.strip(), payload.identifier.strip().lower()))
    row = cursor.fetchone()
    conn.close()

    if not row:
        # Create user automatically for DIU student prototype
        clean_id = payload.identifier.strip()
        user_id = f"usr_{clean_id.replace('-', '_')}"
        email = f"{clean_id}@diu.edu.bd" if "@" not in clean_id else clean_id
        conn = get_db()
        conn.cursor().execute("""
        INSERT INTO users (id, student_id, name, email, phone, password_hash, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (user_id, clean_id, "DIU Student", email, "01712345678", payload.password, datetime.utcnow().isoformat()))
        conn.commit()
        conn.close()

        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        row = cursor.fetchone()
        conn.close()

    user_dict = map_user(row)
    return {
        "token": f"jwt_diu_{row['id']}_{int(datetime.utcnow().timestamp())}",
        "refreshToken": f"refresh_diu_{row['id']}",
        "user": user_dict,
    }

@app.post("/ride/api/auth/register")
@app.post("/api/auth/register")
def auth_register(payload: RegisterPayload):
    conn = get_db()
    cursor = conn.cursor()
    user_id = f"usr_{payload.studentId.strip().replace('-', '_')}"

    cursor.execute("""
    INSERT OR REPLACE INTO users (
        id, student_id, name, email, phone, department, password_hash, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        user_id,
        payload.studentId.strip(),
        payload.name.strip(),
        payload.email.strip().lower(),
        payload.phone.strip(),
        payload.department or "CSE",
        payload.password,
        datetime.utcnow().isoformat(),
    ))
    conn.commit()
    conn.close()

    return {
        "otp": "123456",
        "message": "Registration received. Instant OTP verified.",
    }

@app.post("/ride/api/auth/verify-registration")
@app.post("/ride/api/auth/verify-email")
@app.post("/api/auth/verify-registration")
@app.post("/api/auth/verify-email")
def auth_verify_email(req: Dict[str, Any]):
    email = req.get("email", "").strip().lower()
    student_id = req.get("studentId", "")
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE email = ? OR student_id = ?", (email, student_id))
    row = cursor.fetchone()
    conn.close()

    if row:
        user = map_user(row)
    else:
        user = {
            "id": f"usr_{student_id.replace('-', '_')}",
            "studentId": student_id or "201-15-14285",
            "name": req.get("name", "DIU Student"),
            "email": email or "student@diu.edu.bd",
            "phone": req.get("phone", "01712345678"),
            "department": "CSE",
            "batch": "Batch 54",
            "isDiuVerified": True,
            "role": "student",
            "rating": 4.90,
            "totalRidesAsPassenger": 0,
            "totalRidesAsDriver": 0,
            "isDriverRegistered": False,
        }

    return {"user": user, "token": f"jwt_verified_{user['id']}"}

# =====================================================================
# REST Endpoints: Rides
# =====================================================================

@app.get("/ride/api/rides")
@app.get("/api/rides")
def get_rides(
    status: Optional[str] = "published",
    pickup: Optional[str] = None,
    dropoff: Optional[str] = None,
    vehicle_type: Optional[str] = None,
    female_only: Optional[bool] = None,
):
    conn = get_db()
    cursor = conn.cursor()
    query = "SELECT * FROM rides WHERE 1=1"
    params = []

    if status:
        query += " AND status = ?"
        params.append(status)
    if vehicle_type:
        query += " AND vehicle_type = ?"
        params.append(vehicle_type)
    if female_only is not None:
        query += " AND is_female_only = ?"
        params.append(1 if female_only else 0)

    query += " ORDER BY departure_time ASC"
    cursor.execute(query, params)
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
async def start_ride(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE rides SET status = 'active' WHERE id = ?", (ride_id,))
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
async def complete_ride(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE rides SET status = 'completed' WHERE id = ?", (ride_id,))
    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
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
        msg_data.get("text", ""),
        msg_data.get("timestamp", datetime.utcnow().isoformat()),
        1 if msg_data.get("isRead", True) else 0,
        1 if msg_data.get("isLocationShare", False) else 0,
        msg_data.get("sharedLat"),
        msg_data.get("sharedLng"),
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
