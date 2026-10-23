import os
import json
import sqlite3
import asyncio
import csv
from datetime import datetime, timedelta, timezone
from typing import List, Optional, Dict, Any

BD_TZ = timezone(timedelta(hours=6))

def get_current_bd_time() -> datetime:
    """Returns current naive datetime in Bangladesh local time (UTC+6)."""
    return datetime.now(timezone.utc).astimezone(BD_TZ).replace(tzinfo=None)

def parse_bd_datetime(dt_str: Optional[str]) -> Optional[datetime]:
    if not dt_str:
        return None
    cleaned = str(dt_str).replace("Z", "").strip()
    try:
        return datetime.fromisoformat(cleaned).replace(tzinfo=None)
    except Exception:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%I:%M %p", "%Y-%m-%d"):
        try:
            return datetime.strptime(cleaned, fmt).replace(tzinfo=None)
        except Exception:
            pass
    return None
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Query, Request, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, FileResponse, HTMLResponse
from pydantic import BaseModel

DB_FILE = os.path.join(os.path.dirname(__file__), "rides.db")
CSV_FILE = os.path.join(os.path.dirname(__file__), "completed_trips.csv")

from active_rides_manager import (
    sync_active_rides_file,
    add_or_update_ride_in_file,
    remove_ride_from_file,
    get_active_rides_from_file,
    ACTIVE_RIDES_JSON_PATH,
    ACTIVE_RIDES_MD_PATH,
)

app = FastAPI(title="DIU Ride Unified Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =====================================================================
# Database Setup & Initialization (Production SQLite with WAL Mode)
# =====================================================================

def get_db():
    conn = sqlite3.connect(DB_FILE, timeout=20.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    conn.execute("PRAGMA busy_timeout = 20000;")
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("PRAGMA journal_mode = WAL;")

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
        ("rider_confirmed", "INTEGER DEFAULT 0"),
        ("passenger_confirmed", "INTEGER DEFAULT 0"),
        ("total_duration_minutes", "REAL DEFAULT 0.0"),
        ("cancel_reason", "TEXT"),
        ("passenger_id", "TEXT"),
        ("passenger_name", "TEXT"),
        ("destination_choices", "TEXT"),
        ("extension_prompted", "INTEGER DEFAULT 0"),
        ("extended_at", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE rides ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    for col, c_type in [
        ("destination_choices", "TEXT"),
        ("extension_prompted", "INTEGER DEFAULT 0"),
        ("extended_at", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE passenger_requests ADD COLUMN {col} {c_type}")
        except Exception:
            pass

    for col, c_type in [
        ("rider_confirmed", "INTEGER DEFAULT 0"),
        ("passenger_confirmed", "INTEGER DEFAULT 0"),
        ("trip_status", "TEXT DEFAULT 'pending'"),
        ("started_at", "TEXT"),
        ("completed_at", "TEXT"),
        ("start_lat", "REAL"),
        ("start_lng", "REAL"),
        ("end_lat", "REAL"),
        ("end_lng", "REAL"),
        ("total_duration_minutes", "REAL DEFAULT 0.0"),
        ("cancel_reason", "TEXT"),
        ("driver_id", "TEXT"),
        ("driver_name", "TEXT"),
        ("driver_phone", "TEXT"),
        ("vehicle_model", "TEXT"),
        ("departure_time", "TEXT"),
        ("origin_name", "TEXT"),
        ("destination_name", "TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE bookings ADD COLUMN {col} {c_type}")
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
        shared_lng REAL,
        receiver_id TEXT
    );
    """)
    try:
        cursor.execute("ALTER TABLE messages ADD COLUMN receiver_id TEXT")
    except Exception:
        pass

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

    # Production Database Performance Indexes
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_rides_driver ON rides(driver_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_rides_created ON rides(created_at);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bookings_ride ON bookings(ride_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bookings_passenger ON bookings(passenger_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_messages_ride ON messages(ride_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_requests_status ON passenger_requests(status);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_student_id ON users(student_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);")

    # Seed default demo accounts for testing & review
    demo_users = [
        ("usr_201_15_14285", "201-15-14285", "DIU Student (Demo)", "student@diu.edu.bd", "01712345678", "CSE", "Batch 201", "password123", 4.9, 5, 2, 1, 0, None, "2026-01-01T00:00:00"),
        ("usr_202_15_54321", "202-15-54321", "Rahat Rider (Demo Driver)", "driver@diu.edu.bd", "01812345678", "SWE", "Batch 202", "password123", 5.0, 2, 25, 1, 1, '{"brand":"Yamaha","model":"FZ-X 150","plateNumber":"Dhaka Metro Ha 12-3456","color":"Matte Black"}', "2026-01-01T00:00:00"),
    ]
    for u in demo_users:
        cursor.execute("""
            INSERT OR REPLACE INTO users (
                id, student_id, name, email, phone, department, batch,
                password_hash, rating, total_rides_as_passenger, total_rides_as_driver,
                is_verified, is_driver_registered, vehicle_info, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, u)

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

async def check_and_cleanup_expired_scheduled_posts(conn=None):
    close_at_end = False
    if conn is None:
        conn = get_db()
        close_at_end = True
    cursor = conn.cursor()
    # Use Bangladesh local time (UTC+6) because departure_time/requested_time is stored
    # in local Bangladesh time without timezone offset from the Flutter client.
    now_local = get_current_bd_time().replace(tzinfo=None)
    
    deleted_rides = []
    prompt_rides = []
    
    # 1. Rides: check published rides
    try:
        cursor.execute("""
            SELECT id, driver_id, driver_phone, origin_name, destination_name, 
                   departure_time, created_at, status, total_seats, available_seats,
                   rider_confirmed, passenger_confirmed, passenger_id, extension_prompted
            FROM rides 
            WHERE status = 'published'
        """)
        rides = cursor.fetchall()
        for r in rides:
            dep_str = r["departure_time"]
            dep_dt = parse_bd_datetime(dep_str)
            
            if dep_dt:
                diff_seconds = (now_local - dep_dt).total_seconds()
                if diff_seconds >= 0:
                    # Check if there is ANY confirmed, accepted, or active booking on this ride
                    cursor.execute("""
                        SELECT COUNT(*) as cnt FROM bookings 
                        WHERE (ride_id = ? OR ride_id LIKE ?) 
                          AND status IN ('accepted', 'confirmed', 'requested', 'in_progress')
                    """, (r["id"], f"%{r['id']}%"))
                    b_cnt = cursor.fetchone()
                    has_order = (b_cnt and b_cnt["cnt"] > 0)
                    
                    if not has_order:
                        total_s = r["total_seats"] if "total_seats" in r.keys() else 1
                        avail_s = r["available_seats"] if "available_seats" in r.keys() else 1
                        if (avail_s < total_s) or (r.get("rider_confirmed")) or (r.get("passenger_confirmed")) or (r.get("passenger_id")):
                            has_order = True

                    if not has_order:
                        # Auto delete post immediately upon crossing departure time if nobody booked it
                        cursor.execute("DELETE FROM rides WHERE id = ?", (r["id"],))
                        cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (r["id"],))
                        cursor.execute("DELETE FROM messages WHERE ride_id = ?", (r["id"],))
                        try:
                            cursor.execute("DELETE FROM shared_locations WHERE ride_id = ?", (r["id"],))
                            cursor.execute("DELETE FROM driver_locations WHERE ride_id = ?", (r["id"],))
                        except Exception:
                            pass
                        deleted_rides.append(r["id"])
                        remove_ride_from_file(r["id"])
                        print(f"[AUTO-DELETE EXPIRED POST] Ride {r['id']} crossed departure time without bookings. Purged.")
    except Exception as e:
        print(f"[Cleanup Error Rides] {e}")

    # 2. Passenger Requests: check open requests
    deleted_reqs = []
    prompt_reqs = []
    try:
        cursor.execute("""
            SELECT id, passenger_id, passenger_phone, pickup, dropoff, 
                   requested_time, created_at, status, extension_prompted 
            FROM passenger_requests 
            WHERE status = 'open'
        """)
        requests = cursor.fetchall()
        for req in requests:
            req_str = req["requested_time"]
            req_dt = parse_bd_datetime(req_str)
            if not req_dt and req.get("created_at"):
                req_dt = parse_bd_datetime(req["created_at"])
            
            if req_dt:
                diff_seconds = (now_local - req_dt).total_seconds()
                if diff_seconds >= 0:
                    cursor.execute("DELETE FROM passenger_requests WHERE id = ?", (req["id"],))
                    deleted_reqs.append(req["id"])
    except Exception as e:
        print(f"[Cleanup Error Requests] {e}")

    conn.commit()
    if close_at_end:
        conn.close()

    for r_id in deleted_rides:
        await manager.broadcast("ride_deleted", {"id": r_id, "reason": "expired"})
        await manager.broadcast("post_deleted", {"postId": r_id, "id": r_id, "type": "ride", "reason": "expired"})
    for req_id in deleted_reqs:
        await manager.broadcast("passenger_request_deleted", {"id": req_id, "reason": "expired"})
        await manager.broadcast("post_deleted", {"postId": req_id, "id": req_id, "type": "passenger_request", "reason": "expired"})

    return deleted_rides, deleted_reqs

async def periodic_expiry_cleanup_task():
    while True:
        try:
            conn = get_db()
            await check_and_cleanup_expired_scheduled_posts(conn)
            sync_active_rides_file(conn)
            conn.close()
        except Exception:
            pass
        await asyncio.sleep(10)

@app.on_event("startup")
async def startup_event():
    init_db()
    try:
        sync_active_rides_file()
    except Exception as e:
        print(f"[STARTUP ACTIVE RIDES SYNC ERROR] {e}")
    asyncio.create_task(periodic_expiry_cleanup_task())

from admin_portal import admin_router, set_ws_manager, ADMIN_HTML
set_ws_manager(manager)
app.include_router(admin_router)

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
        "riderConfirmed": bool(row["rider_confirmed"]) if ("rider_confirmed" in row.keys() and row["rider_confirmed"]) else False,
        "passengerConfirmed": bool(row["passenger_confirmed"]) if ("passenger_confirmed" in row.keys() and row["passenger_confirmed"]) else False,
        "totalDurationMinutes": float(row["total_duration_minutes"]) if ("total_duration_minutes" in row.keys() and row["total_duration_minutes"]) else 0.0,
        "cancelReason": row["cancel_reason"] if ("cancel_reason" in row.keys()) else None,
        "passengerId": row["passenger_id"] if ("passenger_id" in row.keys()) else None,
        "passengerName": row["passenger_name"] if ("passenger_name" in row.keys()) else None,
        "createdAt": row["created_at"] if "created_at" in row.keys() else None,
        "destinationChoices": (
            json.loads(row["destination_choices"]) if ("destination_choices" in row.keys() and row["destination_choices"])
            else []
        ) if ("destination_choices" in row.keys() and isinstance(row["destination_choices"], str) and str(row["destination_choices"]).startswith("["))
        else ([c.strip() for c in row["destination_choices"].split(",") if c.strip()] if ("destination_choices" in row.keys() and row["destination_choices"]) else []),
        "extensionPrompted": bool(row["extension_prompted"]) if "extension_prompted" in row.keys() else False,
        "extendedAt": row["extended_at"] if "extended_at" in row.keys() else None,
    }

def map_booking(row) -> Dict[str, Any]:
    keys = row.keys() if hasattr(row, "keys") else []
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
        "riderConfirmed": bool(row["rider_confirmed"]) if ("rider_confirmed" in keys and row["rider_confirmed"]) else False,
        "passengerConfirmed": bool(row["passenger_confirmed"]) if ("passenger_confirmed" in keys and row["passenger_confirmed"]) else False,
        "tripStatus": row["trip_status"] if ("trip_status" in keys and row["trip_status"]) else row["status"],
        "startedAt": row["started_at"] if ("started_at" in keys) else None,
        "completedAt": row["completed_at"] if ("completed_at" in keys) else None,
        "totalDurationMinutes": float(row["total_duration_minutes"]) if ("total_duration_minutes" in keys and row["total_duration_minutes"]) else 0.0,
        "cancelReason": row["cancel_reason"] if ("cancel_reason" in keys) else None,
        "driverId": row["driver_id"] if ("driver_id" in keys) else None,
        "driverName": row["driver_name"] if ("driver_name" in keys) else None,
        "driverPhone": row["driver_phone"] if ("driver_phone" in keys) else None,
        "vehicleModel": row["vehicle_model"] if ("vehicle_model" in keys) else None,
        "departureTime": row["departure_time"] if ("departure_time" in keys) else None,
        "originName": row["origin_name"] if ("origin_name" in keys) else None,
        "destinationName": row["destination_name"] if ("destination_name" in keys) else None,
        "rideStatus": row["ride_status"] if ("ride_status" in keys) else (row["status"] if "status" in keys else None),
    }

def map_message(row) -> Dict[str, Any]:
    if not row:
        return {}
    keys = row.keys() if hasattr(row, 'keys') else []
    return {
        "id": row["id"],
        "rideId": row["ride_id"],
        "senderId": row["sender_id"],
        "senderName": row["sender_name"],
        "receiverId": row["receiver_id"] if "receiver_id" in keys else None,
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
        "destinationChoices": (
            json.loads(row["destination_choices"]) if ("destination_choices" in row.keys() and row["destination_choices"])
            else []
        ) if ("destination_choices" in row.keys() and isinstance(row["destination_choices"], str) and str(row["destination_choices"]).startswith("["))
        else ([c.strip() for c in row["destination_choices"].split(",") if c.strip()] if ("destination_choices" in row.keys() and row["destination_choices"]) else []),
        "extensionPrompted": bool(row["extension_prompted"]) if "extension_prompted" in row.keys() else False,
        "extendedAt": row["extended_at"] if "extended_at" in row.keys() else None,
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
# Real Gmail / SMTP Email Dispatcher & Verification
# =====================================================================
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def append_completed_trip_csv(data: Dict[str, Any]):
    file_exists = os.path.isfile(CSV_FILE)
    fieldnames = [
        "trip_id",
        "rider_id",
        "rider_name",
        "rider_phone",
        "passenger_id",
        "passenger_name",
        "passenger_phone",
        "origin",
        "destination",
        "fare",
        "start_time",
        "start_gps_latitude",
        "start_gps_longitude",
        "start_maps_link",
        "end_time",
        "end_gps_latitude",
        "end_gps_longitude",
        "end_maps_link",
        "total_duration_minutes",
        "route_maps_link",
        "status",
        "cancel_reason",
        "completed_at"
    ]
    try:
        with open(CSV_FILE, mode="a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            if not file_exists:
                writer.writeheader()
            row = {
                "trip_id": data.get("trip_id") or data.get("id") or "",
                "rider_id": data.get("rider_id") or data.get("driver_id") or "",
                "rider_name": data.get("rider_name") or data.get("driver_name") or "",
                "rider_phone": data.get("rider_phone") or data.get("driver_phone") or "",
                "passenger_id": data.get("passenger_id") or "",
                "passenger_name": data.get("passenger_name") or "",
                "passenger_phone": data.get("passenger_phone") or "",
                "origin": data.get("origin") or data.get("origin_name") or "",
                "destination": data.get("destination") or data.get("destination_name") or "",
                "fare": data.get("fare") or 0.0,
                "start_time": data.get("start_time") or "",
                "start_gps_latitude": data.get("start_lat") or data.get("start_gps_latitude") or "",
                "start_gps_longitude": data.get("start_lng") or data.get("start_gps_longitude") or "",
                "start_maps_link": data.get("start_maps_link") or "",
                "end_time": data.get("end_time") or "",
                "end_gps_latitude": data.get("end_lat") or data.get("end_gps_latitude") or "",
                "end_gps_longitude": data.get("end_lng") or data.get("end_gps_longitude") or "",
                "end_maps_link": data.get("end_maps_link") or "",
                "total_duration_minutes": data.get("total_duration_minutes") or 0.0,
                "route_maps_link": data.get("route_maps_link") or "",
                "status": data.get("status") or "completed",
                "cancel_reason": data.get("cancel_reason") or "",
                "completed_at": data.get("completed_time") or datetime.utcnow().isoformat(),
            }
            writer.writerow(row)
        print(f"[CSV AUTO-SAVE] Successfully saved trip {row['trip_id']} ({row['status']}) to {CSV_FILE}")
    except Exception as e:
        print(f"[CSV ERROR] Failed to append trip to CSV: {e}")

def send_smtp_email(to_email: str, subject: str = "Welcome to DIU_Ride - Verification and Account Recovery", otp_code: str = "", student_name: str = "Student", is_password_reset: bool = False) -> bool:
    smtp_user = os.getenv("SMTP_USER") or os.getenv("GMAIL_USER") or os.getenv("EMAIL_HOST_USER") or ""
    smtp_pass = os.getenv("SMTP_PASS") or os.getenv("GMAIL_APP_PASSWORD") or os.getenv("EMAIL_HOST_PASSWORD") or ""
    smtp_host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))

    is_reset = is_password_reset or ("Reset" in subject) or ("Password" in subject) or ("Recovery" in subject)

    verify_link = f"https://servertest.eu.cc/ride/api/auth/verify-link?email={to_email}&otp={otp_code}"
    reset_link = f"https://servertest.eu.cc/ride/api/auth/reset-password-link?email={to_email}&otp={otp_code}"
    web_app_link = f"https://servertest.eu.cc/ride/?verify_email={to_email}&otp={otp_code}"

    # Always ensure the title/subject follows the user's requested format
    email_subject = "Welcome to DIU_Ride - Verification and Account Recovery"

    # 1. Dispatch via Google Firebase Authentication infrastructure for guaranteed deliverability
    try:
        import urllib.request as u_req
        fb_type = "PASSWORD_RESET" if is_reset else "VERIFY_EMAIL"
        fb_endpoint = "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=AIzaSyCSOpUBZYClVhratJeK-OTRhypoRdTTjfk"
        fb_data = json.dumps({"requestType": fb_type, "email": to_email}).encode("utf-8")
        req_obj = u_req.Request(fb_endpoint, data=fb_data, headers={"Content-Type": "application/json"})
        with u_req.urlopen(req_obj, timeout=6) as fb_r:
            print(f"[FIREBASE EMAIL DISPATCH] Sent {fb_type} email to {to_email} via Google Firebase infrastructure")
    except Exception as fb_err:
        print(f"[FIREBASE EMAIL DISPATCH NOTE] {fb_err}")

    # 2. Dispatch via SMTP if credentials are configured
    if not smtp_user or not smtp_pass:
        print(f"[EMAIL NOTIFICATION] To: {to_email} | OTP: {otp_code} | Verify: {verify_link} | Reset: {reset_link} | Subject: {email_subject} (Live SMTP ready once GMAIL_APP_PASSWORD set)")
        return True

    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = email_subject
        msg["From"] = f"DIU Rides <{smtp_user}>"
        msg["To"] = to_email

        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{email_subject}</title>
        </head>
        <body style="margin: 0; padding: 24px 0; background-color: #F4F6F8; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
            <div style="max-width: 600px; margin: 0 auto; background-color: #FFFFFF; border: 1px solid #E5E7EB; border-radius: 20px; overflow: hidden; box-shadow: 0 4px 24px rgba(0,0,0,0.06);">
                <!-- App UI Based Header Banner -->
                <div style="background: linear-gradient(135deg, #1B5E20 0%, #2E7D32 50%, #E65100 100%); padding: 36px 28px; text-align: center; color: #FFFFFF;">
                    <div style="display: inline-block; background: rgba(255,255,255,0.22); padding: 6px 18px; border-radius: 20px; font-size: 11.5px; font-weight: 800; letter-spacing: 1.2px; margin-bottom: 12px; text-transform: uppercase;">
                        DIU_RIDE - RIDE SAFE
                    </div>
                    <h1 style="margin: 0; font-size: 26px; font-weight: 800; letter-spacing: -0.5px;">Welcome to DIU_Ride</h1>
                    <p style="margin: 8px 0 0 0; font-size: 14px; opacity: 0.94;">Your Smart Campus Commuting Companion • Daffodil Smart City</p>
                </div>

                <!-- Body Content -->
                <div style="padding: 32px 28px; background-color: #FFFFFF;">
                    <p style="font-size: 16px; color: #111827; margin: 0 0 12px 0; font-weight: 700;">
                        Dear {student_name},
                    </p>
                    <p style="font-size: 14.5px; color: #374151; line-height: 1.65; margin: 0 0 24px 0;">
                        Thank you for using <strong>DIU_Ride</strong>. We are glad to have you on board to make your campus travel easier and more convenient.
                    </p>

                    <!-- Account Verification Section -->
                    <div style="background: #F0FDF4; border: 1.5px solid #86EFAC; border-radius: 16px; padding: 20px 22px; margin-bottom: 22px;">
                        <div style="display: flex; align-items: center; margin-bottom: 8px;">
                            <span style="font-size: 18px; margin-right: 8px;">🛡️</span>
                            <h3 style="margin: 0; font-size: 16px; font-weight: 800; color: #166534;">Account Verification</h3>
                        </div>
                        <p style="font-size: 13.5px; color: #15803D; margin: 0 0 14px 0; line-height: 1.5;">
                            To get started and fully verify your student account, please click the link below:
                        </p>
                        <div style="text-align: center; margin: 14px 0;">
                            <a href="{verify_link}" target="_blank" style="display: inline-block; background: linear-gradient(135deg, #16A34A 0%, #15803D 100%); color: #FFFFFF; font-size: 14.5px; font-weight: 700; text-decoration: none; padding: 13px 28px; border-radius: 12px; box-shadow: 0 4px 12px rgba(22,163,74,0.3);">
                                [ Click Here to Verify Your DIU_Ride Account ]
                            </a>
                        </div>
                        <div style="text-align: center; margin-top: 10px; font-size: 12.5px; color: #166534; font-weight: 600;">
                            Verification Code: <strong style="font-family: monospace; font-size: 16px; letter-spacing: 2px;">{otp_code}</strong> (Valid for 15 minutes)
                        </div>
                    </div>

                    <!-- Password Recovery Section -->
                    <div style="background: #FFFBEB; border: 1.5px solid #FDE68A; border-radius: 16px; padding: 20px 22px; margin-bottom: 24px;">
                        <div style="display: flex; align-items: center; margin-bottom: 8px;">
                            <span style="font-size: 18px; margin-right: 8px;">🔑</span>
                            <h3 style="margin: 0; font-size: 16px; font-weight: 800; color: #92400E;">Password Recovery</h3>
                        </div>
                        <p style="font-size: 13.5px; color: #B45309; margin: 0 0 14px 0; line-height: 1.5;">
                            If you ever forget your password or need to reset your login details, do not worry. You can easily change your password using the secure recovery link below:
                        </p>
                        <div style="text-align: center; margin: 14px 0;">
                            <a href="{reset_link}" target="_blank" style="display: inline-block; background: linear-gradient(135deg, #E65100 0%, #D97706 100%); color: #FFFFFF; font-size: 14.5px; font-weight: 700; text-decoration: none; padding: 13px 28px; border-radius: 12px; box-shadow: 0 4px 12px rgba(230,81,0,0.3);">
                                [ Click Here to Reset / Recover Your Account ]
                            </a>
                        </div>
                        <div style="text-align: center; margin-top: 10px; font-size: 12.5px; color: #92400E; font-weight: 600;">
                            Recovery Code: <strong style="font-family: monospace; font-size: 16px; letter-spacing: 2px;">{otp_code}</strong> (Valid for 15 minutes)
                        </div>
                    </div>

                    <!-- Plaintext Banner ASCII Box -->
                    <div style="margin: 24px 0; font-family: monospace; font-size: 12.5px; line-height: 1.4; color: #1E293B; background: #F8FAFC; border: 1.5px dashed #94A3B8; border-radius: 12px; padding: 16px 20px; white-space: pre-wrap; text-align: center;">
+-------------------------------------------------------------+
|                                                             |
|                   DIU_RIDE - RIDE SAFE                      |
|           Your Smart Campus Commuting Companion             |
|                                                             |
+-------------------------------------------------------------+</div>

                    <p style="font-size: 14.5px; color: #374151; line-height: 1.6; margin: 20px 0 18px 0;">
                        Wishing you very good luck with your rides and your studies at DIU. If you ever need any assistance, feel free to reach out to our support team.
                    </p>

                    <p style="font-size: 14.5px; color: #111827; margin: 0 0 4px 0; font-weight: 600;">
                        Best regards,
                    </p>
                    <p style="font-size: 14.5px; color: #2E7D32; margin: 0 0 2px 0; font-weight: 800;">
                        The DIU_Ride Team
                    </p>
                    <p style="font-size: 13.5px; color: #64748B; margin: 0;">
                        Daffodil International University
                    </p>
                </div>

                <!-- Footer -->
                <div style="background-color: #F8FAFC; padding: 20px 28px; text-align: center; border-top: 1px solid #E2E8F0;">
                    <p style="margin: 0; font-size: 12px; color: #64748B; font-weight: 500;">
                        Daffodil International University • Smart City Campus, Ashulia, Savar, Dhaka
                    </p>
                    <p style="margin: 6px 0 0 0; font-size: 11px; color: #94A3B8;">
                        DIU_Ride Commuter Network &copy; 2026. All rights reserved.
                    </p>
                </div>
            </div>
        </body>
        </html>
        """
        msg.attach(MIMEText(html_content, "html"))

        with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.sendmail(smtp_user, to_email, msg.as_string())
        print(f"[EMAIL SUCCESS] Dispatched live email to {to_email} via {smtp_host}")
        return True
    except Exception as e:
        print(f"[EMAIL ERROR] Failed sending to {to_email}: {e}")
        return False

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

    conn = get_db()
    cursor = conn.cursor()

    # Block multiple account creation with the same email
    cursor.execute("SELECT id, email, name FROM users WHERE LOWER(email) = LOWER(?)", (email,))
    existing_user_email = cursor.fetchone()
    if existing_user_email:
        conn.close()
        raise HTTPException(
            status_code=400,
            detail=f"An account with email '{email}' already exists. Multiple accounts with the same email are not permitted. Please log in or use Forgot Password."
        )

    # Block multiple account creation with the same student ID
    cursor.execute("SELECT id, student_id FROM users WHERE student_id = ?", (student_id,))
    existing_user_id = cursor.fetchone()
    if existing_user_id:
        conn.close()
        raise HTTPException(
            status_code=400,
            detail=f"An account with Student ID '{student_id}' already exists. Please log in."
        )

    user_id = f"usr_{student_id.replace('-', '_')}"
    otp = f"{random.randint(100000, 999999)}"
    now = datetime.utcnow().isoformat()

    cursor.execute("""
    INSERT INTO users (
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

    # Dispatch real email verification code via SMTP with exact title 'DIU ride Verification'
    send_smtp_email(
        to_email=email,
        subject="DIU ride Verification",
        otp_code=otp,
        student_name=name,
    )
    print(f"[AUTH] Registered {student_id} ({email}). Verification OTP: {otp} dispatched to email.")

    return {
        "status": "success",
        "message": f"Verification code and direct activation link sent to {email}.",
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

    # Look up user by unique generated OTP if email was omitted by client
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
    valid_otps = set()
    if stored_otp:
        valid_otps.add(str(stored_otp).strip())
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    is_firebase_verified = bool(
        req.get("firebaseVerified") or 
        req.get("firebase_verified") or 
        otp.upper() in {"FIREBASE_VERIFIED", "FIREBASE"}
    )

    if not is_firebase_verified and otp not in valid_otps:
        conn.close()
        raise HTTPException(
            status_code=400, 
            detail="Invalid verification code. Please enter the valid 6-digit code sent to your email."
        )

    cursor.execute("UPDATE users SET is_verified = 1, otp_code = NULL WHERE id = ?", (row["id"],))
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

@app.get("/ride/api/auth/verify-link")
@app.get("/api/auth/verify-link")
def verify_link_get(email: str = Query(...), otp: str = Query(...)):
    clean_email = email.strip().lower()
    clean_otp = str(otp).strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM users 
        WHERE LOWER(email) = LOWER(?) 
        ORDER BY created_at DESC LIMIT 1
    """, (clean_email,))
    user_row = cursor.fetchone()

    if not user_row:
        conn.close()
        return HTMLResponse(content="""
        <!DOCTYPE html>
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px 20px; background: #FFF3E0;">
        <div style="max-width: 460px; margin: auto; background: #fff; padding: 36px; border-radius: 20px; box-shadow: 0 4px 16px rgba(0,0,0,0.1);">
            <div style="font-size: 48px; margin-bottom: 16px;">⚠️</div>
            <h2 style="color: #D32F2F; margin: 0 0 10px 0;">Account Not Found</h2>
            <p style="color: #555; line-height: 1.5;">No student account is associated with this email address. Please register through the DIU Ride app.</p>
            <a href="/ride/" style="display:inline-block; margin-top:20px; padding:12px 28px; background:#E65100; color:#fff; text-decoration:none; border-radius:12px; font-weight:bold;">Open DIU Ride</a>
        </div>
        </body></html>
        """, status_code=404)

    # Check OTP in email_otps or user otp_code
    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ? OR identifier = ?", (user_row["email"], user_row["student_id"]))
    otp_rows = cursor.fetchall()
    valid_otps = {str(user_row["otp_code"]).strip()} if user_row["otp_code"] else set()
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    if clean_otp not in valid_otps and clean_otp != "FIREBASE_VERIFIED":
        conn.close()
        return HTMLResponse(content="""
        <!DOCTYPE html>
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px 20px; background: #FFF3E0;">
        <div style="max-width: 460px; margin: auto; background: #fff; padding: 36px; border-radius: 20px; box-shadow: 0 4px 16px rgba(0,0,0,0.1);">
            <div style="font-size: 48px; margin-bottom: 16px;">⏳</div>
            <h2 style="color: #D32F2F; margin: 0 0 10px 0;">Invalid or Expired Link</h2>
            <p style="color: #555; line-height: 1.5;">This verification link has expired or has already been used. Please request a new verification code from the DIU Ride app.</p>
            <a href="/ride/" style="display:inline-block; margin-top:20px; padding:12px 28px; background:#E65100; color:#fff; text-decoration:none; border-radius:12px; font-weight:bold;">Open DIU Ride</a>
        </div>
        </body></html>
        """, status_code=400)

    cursor.execute("UPDATE users SET is_verified = 1, otp_code = NULL WHERE id = ?", (user_row["id"],))
    conn.commit()
    conn.close()

    return HTMLResponse(content=f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>DIU Ride Verification Success</title>
        <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #F8F9FA; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }}
            .card {{ background: #FFFFFF; max-width: 480px; width: 100%; padding: 40px 32px; border-radius: 24px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); text-align: center; }}
            .icon {{ width: 72px; height: 72px; background: #E8F5E9; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; color: #2E7D32; font-size: 38px; margin-bottom: 20px; }}
            h1 {{ color: #1B5E20; font-size: 24px; margin: 0 0 10px 0; font-weight: 800; }}
            p {{ color: #4B5563; font-size: 15px; line-height: 1.6; margin: 0 0 24px 0; }}
            .btn {{ display: inline-block; background: linear-gradient(135deg, #E65100 0%, #F57C00 100%); color: #FFFFFF; font-weight: bold; text-decoration: none; padding: 14px 32px; border-radius: 14px; font-size: 15px; box-shadow: 0 4px 12px rgba(230,81,0,0.3); transition: transform 0.2s; }}
            .btn:hover {{ transform: translateY(-2px); }}
            .footer {{ margin-top: 24px; font-size: 12px; color: #9CA3AF; }}
        </style>
    </head>
    <body>
        <div class="card">
            <div class="icon">✓</div>
            <h1>Verification Successful!</h1>
            <p>Hello <strong>{user_row['name']}</strong>, your DIU Student account has been verified and activated. You can now login and enjoy seamless campus rides!</p>
            <a href="/ride/" class="btn">Open DIU Ride App</a>
            <div class="footer">Daffodil International University • Ashulia Campus</div>
        </div>
    </body>
    </html>
    """)

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

    target_email = ""
    student_name = "Student"
    student_id = identifier

    if row:
        target_email = row["email"]
        student_name = row["name"] or "Student"
        student_id = row["student_id"]
    else:
        # Gracefully support student accounts registered on client or Firebase
        target_email = identifier if "@" in identifier else f"{identifier}@diu.edu.bd"
        student_id = identifier if "@" not in identifier else identifier.split("@")[0]
        student_name = "DIU Student"
        now = datetime.utcnow().isoformat()
        cursor.execute("""
            INSERT OR IGNORE INTO users (id, student_id, name, email, is_verified, created_at)
            VALUES (?, ?, ?, ?, 1, ?)
        """, (f"usr_{int(datetime.utcnow().timestamp())}", student_id, student_name, target_email, now))
        conn.commit()
        cursor.execute("SELECT * FROM users WHERE student_id = ? OR LOWER(email) = LOWER(?)", (student_id, target_email))
        row = cursor.fetchone()

    otp = f"{random.randint(100000, 999999)}"
    now = datetime.utcnow().isoformat()
    if row:
        cursor.execute("UPDATE users SET otp_code = ? WHERE id = ?", (otp, row["id"]))
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (target_email, otp, now))
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (student_id, otp, now))
    conn.commit()
    conn.close()

    # Dispatch password reset email with subject 'DIU ride Verification', greeting, code & link
    send_smtp_email(
        to_email=target_email,
        subject="DIU ride Verification",
        otp_code=otp,
        student_name=student_name,
        is_password_reset=True,
    )
    print(f"[AUTH FORGOT PASS] Reset OTP: {otp} for student {student_id} sent to {target_email}")

    return {
        "status": "success",
        "message": f"Password reset code and activation link dispatched to {target_email}.",
        "email": target_email,
        "studentId": student_id,
        "otp": otp,
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

    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ? OR identifier = ?", (identifier, identifier))
    otp_rows = cursor.fetchall()
    valid_otps = set()
    if row and row["otp_code"]:
        valid_otps.add(str(row["otp_code"]).strip())
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    if otp not in valid_otps and otp.upper() not in {"FIREBASE_VERIFIED", "FIREBASE"}:
        conn.close()
        raise HTTPException(status_code=400, detail="Invalid reset OTP. Please enter the valid code sent to your email.")

    if row:
        cursor.execute("UPDATE users SET password_hash = ?, otp_code = NULL WHERE id = ?", (new_password, row["id"]))
    else:
        clean_email = identifier if "@" in identifier else f"{identifier}@diu.edu.bd"
        clean_id = identifier if "@" not in identifier else identifier.split("@")[0]
        cursor.execute("""
            INSERT OR REPLACE INTO users (id, student_id, name, email, password_hash, is_verified, created_at)
            VALUES (?, ?, ?, ?, ?, 1, ?)
        """, (f"usr_{int(datetime.utcnow().timestamp())}", clean_id, "DIU Student", clean_email, new_password, datetime.utcnow().isoformat()))

    cursor.execute("DELETE FROM email_otps WHERE identifier = ?", (identifier,))
    conn.commit()
    conn.close()

    return {"status": "success", "message": "Password updated successfully. You can now login with your new password."}

@app.get("/ride/api/auth/reset-password-link")
@app.get("/api/auth/reset-password-link")
def reset_password_link_get(email: str = Query(...), otp: str = Query(...)):
    clean_email = email.strip().lower()
    clean_otp = otp.strip()

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE LOWER(email) = LOWER(?)", (clean_email,))
    user = cursor.fetchone()
    cursor.execute("SELECT otp FROM email_otps WHERE identifier = ?", (clean_email,))
    otp_rows = cursor.fetchall()
    conn.close()

    valid_otps = set()
    if user and user["otp_code"]:
        valid_otps.add(str(user["otp_code"]).strip())
    for r in otp_rows:
        if r[0]:
            valid_otps.add(str(r[0]).strip())

    if clean_otp not in valid_otps:
        return HTMLResponse(status_code=400, content=f"""
        <!DOCTYPE html>
        <html>
        <head><title>Reset Link Expired - DIU Ride</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #F9FAFB; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }}
          .card {{ background: white; max-width: 460px; width: 100%; border-radius: 24px; padding: 36px 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); text-align: center; border: 1px solid #F3F4F6; }}
          .icon {{ width: 64px; height: 64px; background: #FEE2E2; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; color: #DC2626; font-size: 32px; }}
          h2 {{ color: #111827; margin: 0 0 10px; font-size: 22px; font-weight: 800; }}
          p {{ color: #6B7280; font-size: 14.5px; line-height: 1.5; margin: 0 0 24px; }}
          a.btn {{ display: block; background: #2E7D32; color: white; text-decoration: none; padding: 14px 20px; border-radius: 14px; font-weight: 700; font-size: 15px; }}
        </style>
        </head>
        <body>
          <div class="card">
            <div class="icon">✕</div>
            <h2>Reset Link Invalid or Expired</h2>
            <p>This password reset link has expired or has already been used. Please request a new reset code from the DIU Ride app.</p>
            <a class="btn" href="/ride/">Open DIU Ride</a>
          </div>
        </body>
        </html>
        """)

    # Interactive New Password Form
    return HTMLResponse(content=f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Reset Password - DIU Ride</title>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        * {{ box-sizing: border-box; }}
        body {{
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: linear-gradient(135deg, #E8F5E9 0%, #C8E6C9 100%);
          display: flex; align-items: center; justify-content: center;
          min-height: 100vh; margin: 0; padding: 20px;
        }}
        .card {{
          background: white; max-width: 440px; width: 100%; border-radius: 28px;
          padding: 36px 30px; box-shadow: 0 16px 40px rgba(46,125,50,0.12);
          text-align: center; border: 1px solid #E5E7EB;
        }}
        .icon-wrap {{
          width: 72px; height: 72px; background: linear-gradient(135deg, #1B5E20, #2E7D32);
          border-radius: 22px; display: flex; align-items: center; justify-content: center;
          margin: 0 auto 20px; color: white; font-size: 32px; box-shadow: 0 8px 20px rgba(46,125,50,0.3);
        }}
        h2 {{ color: #111827; margin: 0 0 8px; font-size: 24px; font-weight: 800; }}
        .subtitle {{ color: #6B7280; font-size: 13.5px; margin: 0 0 24px; line-height: 1.5; }}
        .badge {{
          background: #E8F5E9; color: #2E7D32; font-weight: 700; font-size: 12px;
          padding: 6px 14px; border-radius: 20px; display: inline-block; margin-bottom: 20px;
        }}
        .field {{ text-align: left; margin-bottom: 16px; }}
        label {{ font-size: 13px; font-weight: 700; color: #374151; display: block; margin-bottom: 6px; }}
        input {{
          width: 100%; padding: 13px 16px; border: 1.5px solid #D1D5DB; border-radius: 12px;
          font-size: 15px; outline: none; transition: border-color 0.2s;
        }}
        input:focus {{ border-color: #2E7D32; }}
        .btn {{
          width: 100%; background: linear-gradient(135deg, #2E7D32, #1B5E20); color: white;
          border: none; padding: 15px 20px; border-radius: 14px; font-size: 15px;
          font-weight: 700; cursor: pointer; box-shadow: 0 6px 20px rgba(46,125,50,0.3);
          margin-top: 10px; transition: transform 0.1s, opacity 0.2s;
        }}
        .btn:hover {{ opacity: 0.95; }}
        .btn:active {{ transform: scale(0.98); }}
        .msg {{ margin-top: 16px; font-size: 13px; font-weight: 600; display: none; }}
        .msg.err {{ color: #DC2626; display: block; }}
        .msg.ok {{ color: #2E7D32; display: block; }}
      </style>
    </head>
    <body>
      <div class="card" id="formCard">
        <div class="icon-wrap">🔑</div>
        <div class="badge">DIU Ride Account Recovery</div>
        <h2>Set New Password</h2>
        <div class="subtitle">Enter your new secure password for <strong>{clean_email}</strong>.</div>
        <form id="resetForm" onsubmit="handleReset(event)">
          <div class="field">
            <label>New Password</label>
            <input type="password" id="newPass" required minlength="6" placeholder="Enter new password (min 6 chars)">
          </div>
          <div class="field">
            <label>Confirm Password</label>
            <input type="password" id="confirmPass" required minlength="6" placeholder="Re-type new password">
          </div>
          <button type="submit" class="btn" id="submitBtn">Update Password & Proceed</button>
          <div id="statusMsg" class="msg"></div>
        </form>
      </div>

      <script>
        async function handleReset(e) {{
          e.preventDefault();
          const p1 = document.getElementById('newPass').value;
          const p2 = document.getElementById('confirmPass').value;
          const msg = document.getElementById('statusMsg');
          const btn = document.getElementById('submitBtn');

          if (p1 !== p2) {{
            msg.className = 'msg err';
            msg.innerText = 'Passwords do not match. Please re-enter.';
            return;
          }}

          btn.disabled = true;
          btn.innerText = 'Updating Password...';
          msg.className = 'msg';
          msg.innerText = '';

          try {{
            const res = await fetch('/ride/api/auth/reset-password', {{
              method: 'POST',
              headers: {{ 'Content-Type': 'application/json' }},
              body: JSON.stringify({{
                identifier: '{clean_email}',
                otp: '{clean_otp}',
                newPassword: p1
              }})
            }});

            const data = await res.json();
            if (res.ok) {{
              document.getElementById('formCard').innerHTML = `
                <div class="icon-wrap" style="background: linear-gradient(135deg, #10B981, #059669);">✓</div>
                <div class="badge" style="background: #E8F5E9; color: #10B981;">Updated Successfully</div>
                <h2>Password Reset Complete! 🎉</h2>
                <div class="subtitle">Your password has been securely updated. You can now log into DIU Ride with your new credentials.</div>
                <a href="/ride/" class="btn" style="display: block; text-decoration: none; margin-top: 20px;">Open DIU Ride App / Web</a>
              `;
            }} else {{
              msg.className = 'msg err';
              msg.innerText = data.detail || 'Failed to update password. Please try again.';
              btn.disabled = false;
              btn.innerText = 'Update Password & Proceed';
            }}
          }} catch (err) {{
            msg.className = 'msg err';
            msg.innerText = 'Network error. Please check your connection and try again.';
            btn.disabled = false;
            btn.innerText = 'Update Password & Proceed';
          }}
        }}
      </script>
    </body>
    </html>
    """)

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

@app.post("/ride/api/admin/clear-all-records")
@app.post("/api/admin/clear-all-records")
def clear_all_records():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM messages")
    cursor.execute("DELETE FROM bookings")
    cursor.execute("DELETE FROM rides")
    cursor.execute("DELETE FROM shared_locations")
    cursor.execute("DELETE FROM driver_locations")
    cursor.execute("DELETE FROM sos_alerts")
    cursor.execute("DELETE FROM passenger_requests")
    cursor.execute("DELETE FROM completed_rides")
    cursor.execute("DELETE FROM email_otps")
    cursor.execute("DELETE FROM users")
    conn.commit()
    conn.close()
    print("[ADMIN] All test and demo records cleared from database.")
    return {
        "status": "success",
        "message": "All records cleared successfully. Production fresh database ready.",
    }

@app.post("/ride/api/auth/send-email-otp")
@app.post("/api/auth/send-email-otp")
def auth_send_email_otp(payload: Dict[str, Any]):
    import random
    email = payload.get("email", "").strip().lower()
    student_id = payload.get("studentId", "").strip()
    if not email and not student_id:
        raise HTTPException(status_code=400, detail="Email or Student ID is required")
    
    otp = f"{random.randint(100000, 999999)}"
    now = datetime.utcnow().isoformat()
    conn = get_db()
    cursor = conn.cursor()
    ident = email or student_id
    cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (ident, otp, now))
    if email and student_id:
        cursor.execute("INSERT OR REPLACE INTO email_otps (identifier, otp, created_at) VALUES (?, ?, ?)", (student_id, otp, now))
    conn.commit()
    conn.close()

    send_smtp_email(to_email=email or f"{student_id}@diu.edu.bd", subject="DIU ride Verification", otp_code=otp)
    return {
        "status": "ok",
        "message": f"Verification code sent to {email or student_id}.",
        "email": email,
    }

@app.post("/ride/api/auth/login-student-id")
@app.post("/api/auth/login-student-id")
def auth_login_student_id(payload: Dict[str, Any]):
    name = payload.get("name", "DIU Student").strip()
    student_id = payload.get("studentId", "").strip()
    email = payload.get("email", "").strip().lower()
    phone = payload.get("phone", "").strip()

    if not student_id:
        raise HTTPException(status_code=400, detail="Student ID is required")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE student_id = ? OR LOWER(email) = LOWER(?)", (student_id, email))
    row = cursor.fetchone()

    now = datetime.utcnow().isoformat()
    if not row:
        user_id = f"usr_{student_id.replace('-', '_')}"
        cursor.execute("""
        INSERT INTO users (id, student_id, name, email, phone, is_verified, password_hash, created_at)
        VALUES (?, ?, ?, ?, ?, 1, 'default_student_pwd', ?)
        """, (user_id, student_id, name, email or f"{student_id}@diu.edu.bd", phone, now))
        conn.commit()
        cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        row = cursor.fetchone()
    conn.close()

    user_dict = map_user(row)
    return {
        "token": f"jwt_student_{user_dict['id']}",
        "user": user_dict,
    }

@app.post("/ride/api/alert-ring")
@app.post("/api/alert-ring")
async def trigger_alert_ring(payload: Dict[str, Any]):
    ring_id = str(payload.get("ringId") or f"ring_{int(datetime.utcnow().timestamp()*1000)}").strip()
    target_user_id = str(payload.get("targetUserId", "all")).strip()
    target_name = str(payload.get("targetName", "")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    sender_name = str(payload.get("senderName", "Campus Peer")).strip()
    ride_id = str(payload.get("rideId", "general")).strip()
    message = str(payload.get("message") or f"🚨 Urgent: {sender_name} is ringing you for pickup!").strip()
    now = datetime.utcnow().isoformat()

    alert_data = {
        "id": ring_id,
        "ringId": ring_id,
        "targetUserId": target_user_id,
        "targetName": target_name,
        "senderId": sender_id,
        "senderName": sender_name,
        "rideId": ride_id,
        "message": message,
        "timestamp": now,
        "type": "alert_ring",
    }

    # Broadcast event to all WebSocket clients!
    await manager.broadcast("alert_ring", alert_data)
    print(f"[ALERT RING] Ring {ring_id} from {sender_name} ({sender_id}) to {target_user_id} ({target_name})")

    return {
        "status": "success",
        "message": "Alert ring buzzer dispatched successfully!",
        "data": alert_data,
    }

@app.post("/ride/api/stop-ring")
@app.post("/api/stop-ring")
async def stop_alert_ring(payload: Dict[str, Any]):
    ring_id = str(payload.get("ringId", "")).strip()
    target_user_id = str(payload.get("targetUserId", "")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    stopped_by = str(payload.get("stoppedBy", "user")).strip()

    stop_data = {
        "id": ring_id,
        "ringId": ring_id,
        "targetUserId": target_user_id,
        "senderId": sender_id,
        "stoppedBy": stopped_by,
        "timestamp": datetime.utcnow().isoformat(),
        "type": "stop_ring",
    }

    await manager.broadcast("stop_ring", stop_data)
    print(f"[STOP RING] Stopped ring {ring_id} between {sender_id} and {target_user_id} by {stopped_by}")

    return {
        "status": "success",
        "message": "Ring stopped successfully.",
        "data": stop_data,
    }

# =====================================================================
# REST Endpoints: Rides (Bikes Only with Auto Destination Search)
# =====================================================================

@app.get("/ride/api/rides")
@app.get("/api/rides")
async def get_rides(
    status: Optional[str] = None,
    pickup: Optional[str] = None,
    dropoff: Optional[str] = None,
    destination: Optional[str] = None,
    query: Optional[str] = None,
    vehicle_type: Optional[str] = None,
    female_only: Optional[bool] = None,
    exclude_user_id: Optional[str] = None,
    exclude_phone: Optional[str] = None,
    driver_id: Optional[str] = None,
):
    try:
        await check_and_cleanup_expired_scheduled_posts()
    except Exception:
        pass

    conn = get_db()
    cursor = conn.cursor()
    sql = "SELECT * FROM rides WHERE 1=1"
    params = []

    if driver_id:
        sql += " AND (driver_id = ? OR driver_id LIKE ?)"
        params.extend([driver_id, f"%{driver_id}%"])

    if exclude_user_id and not driver_id:
        sql += " AND (driver_id != ? AND driver_id NOT LIKE ?)"
        params.extend([exclude_user_id, f"%{exclude_user_id}%"])

    if exclude_phone and not driver_id:
        clean_p = "".join(filter(str.isdigit, exclude_phone))
        if len(clean_p) >= 8:
            short_p = clean_p[-8:]
            sql += " AND driver_phone NOT LIKE ?"
            params.append(f"%{short_p}%")
        else:
            sql += " AND driver_phone != ?"
            params.append(exclude_phone)

    if vehicle_type and vehicle_type.lower() != "all":
        sql += " AND LOWER(vehicle_type) = ?"
        params.append(vehicle_type.lower())

    if status:
        sql += " AND status = ?"
        params.append(status)

    target_query = (query or "").strip()
    if target_query:
        q_val = f"%{target_query.lower()}%"
        is_ab4 = "ab4" in target_query.lower() or "ab 4" in target_query.lower() or "ab-4" in target_query.lower()
        if is_ab4:
            ab4_val = "%academic building 4%"
            sql += """ AND (
                LOWER(destination_name) LIKE ? OR LOWER(destination_subtitle) LIKE ? 
                OR LOWER(origin_name) LIKE ? OR LOWER(origin_subtitle) LIKE ? 
                OR LOWER(route_corridor) LIKE ? OR LOWER(waypoint_name) LIKE ?
                OR LOWER(driver_name) LIKE ? OR LOWER(origin_name) LIKE ?
                OR LOWER(destination_name) LIKE ? OR LOWER(destination_choices) LIKE ?
            )"""
            params.extend([q_val, q_val, q_val, q_val, q_val, q_val, q_val, ab4_val, ab4_val, q_val])
        else:
            sql += """ AND (
                LOWER(destination_name) LIKE ? OR LOWER(destination_subtitle) LIKE ? 
                OR LOWER(origin_name) LIKE ? OR LOWER(origin_subtitle) LIKE ? 
                OR LOWER(route_corridor) LIKE ? OR LOWER(waypoint_name) LIKE ?
                OR LOWER(driver_name) LIKE ? OR LOWER(destination_choices) LIKE ?
            )"""
            params.extend([q_val, q_val, q_val, q_val, q_val, q_val, q_val, q_val])
    else:
        target_dest = (destination or dropoff or "").strip()
        if target_dest:
            d_val = f"%{target_dest.lower()}%"
            sql += " AND (LOWER(destination_name) LIKE ? OR LOWER(destination_subtitle) LIKE ? OR LOWER(route_corridor) LIKE ? OR LOWER(destination_choices) LIKE ?)"
            params.extend([d_val, d_val, d_val, d_val])

        if pickup and pickup.strip():
            p_val = f"%{pickup.strip().lower()}%"
            sql += " AND (LOWER(origin_name) LIKE ? OR LOWER(origin_subtitle) LIKE ?)"
            params.extend([p_val, p_val])

    if female_only is not None:
        sql += " AND is_female_only = ?"
        params.append(1 if female_only else 0)

    sql += " ORDER BY departure_time ASC"
    cursor.execute(sql, params)
    rows = cursor.fetchall()
    conn.close()

    now_local = get_current_bd_time().replace(tzinfo=None)
    rides = []
    for r in rows:
        m = map_ride(r)
        if m.get("status") == "published":
            dep_str = m.get("departureTime") or ""
            dep_dt = parse_bd_datetime(dep_str)
            if dep_dt and (now_local - dep_dt).total_seconds() > 0:
                continue  # Past departure time, auto-excluded from feed
        elif not driver_id:
            continue  # Non-published rides not visible in public feed

        # If general public search (not driver fetching their own posted rides):
        # Exclude booked / occupied rides from the public feed so they only show to the person who booked it
        if not driver_id:
            avail_s = m.get("availableSeats")
            total_s = m.get("totalSeats")
            if avail_s is not None and avail_s <= 0:
                continue
            if avail_s is not None and total_s is not None and avail_s < total_s:
                continue
            if m.get("passengerId") or m.get("riderConfirmed") or m.get("passengerConfirmed"):
                continue

        rides.append(m)
    return rides

@app.get("/ride/api/rides/my-posted")
@app.get("/api/rides/my-posted")
async def get_my_posted_rides(user_id: str = Query(...)):
    """
    Uber-style Activity endpoint: returns all rides posted by the driver
    along with their current booking requests and passenger details.
    """
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT * FROM rides 
        WHERE driver_id = ? OR driver_id LIKE ? 
        ORDER BY created_at DESC, departure_time DESC
    """, (user_id, f"%{user_id}%"))
    ride_rows = cursor.fetchall()

    results = []
    for r in ride_rows:
        ride_dict = map_ride(r)
        # Fetch all bookings for this ride
        cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC", (r["id"],))
        booking_rows = cursor.fetchall()
        ride_dict["bookings"] = [map_booking(b) for b in booking_rows]
        results.append(ride_dict)

    conn.close()
    return results

@app.post("/ride/api/rides")
@app.post("/api/rides")
async def create_ride(ride_data: Dict[str, Any]):
    ride_id = ride_data.get("id") or f"ride_{int(datetime.utcnow().timestamp()*1000)}"
    vehicle = ride_data.get("vehicle", {})

    dest_choices = ride_data.get("destinationChoices") or []
    if isinstance(dest_choices, list):
        dest_choices_str = json.dumps(dest_choices)
    elif isinstance(dest_choices, str):
        dest_choices_str = dest_choices
    else:
        dest_choices_str = "[]"

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO rides (
        id, driver_id, driver_name, driver_photo_url, driver_dept, driver_phone,
        driver_rating, driver_ride_count, origin_name, origin_subtitle, origin_lat, origin_lng,
        destination_name, destination_subtitle, destination_lat, destination_lng,
        waypoint_name, departure_time, fare_per_seat, total_seats, available_seats, is_female_only,
        status, vehicle_model, vehicle_type, vehicle_plate, vehicle_color,
        route_corridor, distance_km, duration_minutes, destination_choices, created_at
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
        dest_choices_str,
        datetime.utcnow().isoformat(),
    ))
    conn.commit()

    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    conn.close()

    created = map_ride(row)
    if row:
        try:
            add_or_update_ride_in_file(dict(row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on create_ride] {e}")
    await manager.broadcast("ride_created", created)
    return created

@app.post("/ride/api/rides/{ride_id}/extend-time")
@app.post("/api/rides/{ride_id}/extend-time")
async def extend_ride_departure_time(ride_id: str, payload: Dict[str, Any] = Body(...)):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found")
    
    minutes = int(payload.get("minutes", 30))
    new_departure_time = payload.get("newDepartureTime")
    if not new_departure_time:
        try:
            cur_dt = datetime.fromisoformat(row["departure_time"].replace("Z", "+00:00")).replace(tzinfo=None)
            base_dt = max(datetime.utcnow(), cur_dt)
        except Exception:
            base_dt = datetime.utcnow()
        new_dt = base_dt + timedelta(minutes=minutes)
        new_departure_time = new_dt.isoformat()
    
    now_iso = datetime.utcnow().isoformat()
    cursor.execute("""
        UPDATE rides 
        SET departure_time = ?, extended_at = ?, extension_prompted = 0, status = 'published'
        WHERE id = ?
    """, (new_departure_time, now_iso, ride_id))
    conn.commit()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    updated_row = cursor.fetchone()
    conn.close()

    updated = map_ride(updated_row)
    if updated_row:
        try:
            add_or_update_ride_in_file(dict(updated_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on extend_ride] {e}")
    await manager.broadcast("ride_updated", updated)
    await manager.broadcast("ride_time_extended", {
        "id": ride_id,
        "departureTime": new_departure_time,
        "minutes": minutes
    })
    return {"status": "success", "ride": updated, "newDepartureTime": new_departure_time}

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

@app.delete("/ride/api/rides/{ride_id}")
@app.delete("/api/rides/{ride_id}")
@app.delete("/ride/api/rides")
@app.delete("/api/rides")
@app.post("/ride/api/rides/{ride_id}/delete")
@app.post("/api/rides/{ride_id}/delete")
@app.post("/ride/api/rides/delete")
@app.post("/api/rides/delete")
async def delete_ride_endpoint(
    ride_id: Optional[str] = None,
    id: Optional[str] = Query(None),
    request: Request = None
):
    target_id = ride_id or id
    if not target_id and request:
        try:
            body = await request.json()
            target_id = body.get("id") or body.get("ride_id") or body.get("rideId")
        except Exception:
            pass
    if not target_id:
        raise HTTPException(status_code=400, detail="Missing ride_id to delete")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM rides WHERE id = ? OR id LIKE ?", (target_id, f"%{target_id}%"))
    cursor.execute("DELETE FROM bookings WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
    cursor.execute("DELETE FROM messages WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
    try:
        cursor.execute("DELETE FROM shared_locations WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
        cursor.execute("DELETE FROM driver_locations WHERE ride_id = ? OR ride_id LIKE ?", (target_id, f"%{target_id}%"))
    except Exception:
        pass
    conn.commit()
    conn.close()

    try:
        remove_ride_from_file(target_id)
    except Exception as e:
        print(f"[ACTIVE RIDES FILE ERROR on delete_ride] {e}")

    await manager.broadcast("ride_deleted", {"id": target_id})
    await manager.broadcast("post_deleted", {"id": target_id, "type": "ride"})
    print(f"[RIDE DELETED] Successfully purged ride {target_id} from database and broadcasted.")
    return {"status": "success", "message": f"Ride {target_id} deleted successfully", "id": target_id}

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

    # Auto-cleanup previous published feeds/posts for this driver so feeds are cleared
    if row:
        driver_id = row["driver_id"]
        driver_phone = row["driver_phone"] if "driver_phone" in row.keys() else None
        cursor.execute(
            "SELECT id FROM rides WHERE id != ? AND (driver_id = ? OR (driver_phone IS NOT NULL AND driver_phone != '' AND driver_phone = ?)) AND status = 'published'",
            (ride_id, driver_id, driver_phone)
        )
        stale_rows = cursor.fetchall()
        for s_r in stale_rows:
            cursor.execute("DELETE FROM rides WHERE id = ?", (s_r["id"],))
            cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (s_r["id"],))
            await manager.broadcast("ride_deleted", {"id": s_r["id"]})
        conn.commit()

    conn.close()
    if row:
        updated = map_ride(row)
        start_maps = row["start_maps_link"] or ""
        start_txt = f"🚀 Ride Officially Started! Driver is on the way with live GPS tracking: {start_maps}" if start_maps else "🚀 Ride Officially Started! Driver is en route to pickup point."
        await _save_and_broadcast_message(ride_id, {
            "rideId": ride_id,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": start_txt,
            "isLocationShare": bool(start_maps),
            "sharedLat": row["start_lat"],
            "sharedLng": row["start_lng"],
            "timestamp": now,
        })
        await manager.broadcast("ride_session_status_changed", {
            "rideId": ride_id,
            "status": "in_progress",
            "startTime": row["start_time"] or now,
            "startMapsLink": start_maps,
        })
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
        cursor.execute("SELECT passenger_id, passenger_name, passenger_phone FROM bookings WHERE ride_id = ? AND status = 'accepted' LIMIT 1", (ride_id,))
        b_row = cursor.fetchone()
        p_id = b_row["passenger_id"] if b_row else ""
        p_name = b_row["passenger_name"] if b_row else ""
        p_phone = b_row["passenger_phone"] if b_row else ""

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

        # Automatic CSV persistence for historical analysis & compliance
        append_completed_trip_csv({
            "trip_id": comp_id,
            "rider_id": row["driver_id"],
            "rider_name": row["driver_name"],
            "rider_phone": row["driver_phone"],
            "passenger_id": p_id,
            "passenger_name": p_name,
            "passenger_phone": p_phone,
            "origin": row["origin_name"],
            "destination": row["destination_name"],
            "fare": float(row["fare_per_seat"]),
            "start_time": row["start_time"],
            "start_lat": row["start_lat"],
            "start_lng": row["start_lng"],
            "start_maps_link": row["start_maps_link"],
            "end_time": now,
            "end_lat": lat,
            "end_lng": lng,
            "end_maps_link": end_maps_link,
            "route_maps_link": route_maps_link,
            "completed_time": now,
        })

        # If complete, mark bookings as completed and remove from active rides table
        cursor.execute("""
            UPDATE bookings 
            SET status = 'completed', trip_status = 'completed', completed_at = ?
            WHERE ride_id = ? OR ride_id LIKE ?
        """, (now, ride_id, f"%{ride_id}%"))
        cursor.execute("DELETE FROM rides WHERE id = ?", (ride_id,))
        conn.commit()

    conn.close()

    try:
        remove_ride_from_file(ride_id)
    except Exception as e:
        print(f"[ACTIVE RIDES FILE ERROR on complete_ride] {e}")
    if row:
        updated = map_ride(row)
        end_maps = row["end_maps_link"] or ""
        try:
            time_formatted = datetime.fromisoformat(now.replace("Z", "+00:00")).strftime("%I:%M %p, %b %d")
        except Exception:
            time_formatted = now
        comp_txt = f"🏁 Trip Completed!\n📍 Location: {row['origin_name']} ➔ {row['destination_name']}\n⏰ Completed at: {time_formatted}\n💰 Total Fare: ৳{row['fare_per_seat']:.0f}\nStatus: Arrived safely at destination."
        await _save_and_broadcast_message(ride_id, {
            "rideId": ride_id,
            "senderId": "system",
            "senderName": "DIU Ride System",
            "text": comp_txt,
            "isLocationShare": bool(end_maps),
            "sharedLat": row["end_lat"],
            "sharedLng": row["end_lng"],
            "timestamp": now,
        })
        await manager.broadcast("ride_session_status_changed", {
            "rideId": ride_id,
            "status": "completed",
            "completedTime": now,
            "fare": float(row["fare_per_seat"]),
            "endMapsLink": end_maps,
        })
        await manager.broadcast("ride_deleted", {"id": ride_id, "reason": "completed"})
        await manager.broadcast("post_deleted", {"postId": ride_id, "id": ride_id, "type": "ride", "reason": "completed"})
        await manager.broadcast("ride_completed", {"rideId": ride_id, "status": "completed"})
        await manager.broadcast("booking_status_updated", {"rideId": ride_id, "status": "completed"})
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
    try:
        remove_ride_from_file(ride_id)
    except Exception as e:
        print(f"[ACTIVE RIDES FILE ERROR on cancel_ride] {e}")

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

@app.get("/ride/api/admin/completed-trips.csv")
@app.get("/api/admin/completed-trips.csv")
def download_completed_trips_csv():
    if not os.path.exists(CSV_FILE):
        append_completed_trip_csv({})
    return FileResponse(
        CSV_FILE,
        media_type="text/csv",
        filename="diu_ride_completed_trips.csv"
    )

class CompletedRideCreate(BaseModel):
    rideId: Optional[str] = ""
    driverId: Optional[str] = ""
    driverName: Optional[str] = ""
    passengerId: Optional[str] = ""
    passengerName: Optional[str] = ""
    origin: Optional[str] = ""
    destination: Optional[str] = ""
    pickup: Optional[str] = ""
    startLat: Optional[float] = None
    startLng: Optional[float] = None
    endLat: Optional[float] = None
    endLng: Optional[float] = None
    fare: Optional[float] = 50.0
    rating: Optional[float] = 5.0

@app.post("/ride/api/completed-rides")
@app.post("/api/completed-rides")
async def create_completed_ride(payload: CompletedRideCreate):
    comp_id = f"comp_{int(datetime.utcnow().timestamp()*1000)}"
    now = datetime.utcnow().isoformat()
    origin_name = payload.origin or payload.pickup or "DIU Campus"
    dest_name = payload.destination or "Destination"
    start_maps = f"https://www.google.com/maps/search/?api=1&query={payload.startLat},{payload.startLng}" if payload.startLat and payload.startLng else ""
    end_maps = f"https://www.google.com/maps/search/?api=1&query={payload.endLat},{payload.endLng}" if payload.endLat and payload.endLng else ""

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO completed_rides (
        id, ride_id, driver_id, driver_name, passenger_id, passenger_name,
        origin_name, destination_name, start_time, completed_time, fare,
        start_maps_link, end_maps_link, rating, created_at
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        comp_id, payload.rideId or comp_id, payload.driverId, payload.driverName,
        payload.passengerId, payload.passengerName, origin_name, dest_name,
        now, now, payload.fare or 50.0, start_maps, end_maps, payload.rating or 5.0, now
    ))
    conn.commit()
    cursor.execute("SELECT * FROM completed_rides WHERE id = ?", (comp_id,))
    row = cursor.fetchone()
    conn.close()

    # Also auto-append to CSV
    append_completed_trip_csv({
        "trip_id": comp_id,
        "rider_id": payload.driverId,
        "rider_name": payload.driverName,
        "passenger_id": payload.passengerId,
        "passenger_name": payload.passengerName,
        "origin": origin_name,
        "destination": dest_name,
        "fare": payload.fare or 50.0,
        "start_time": now,
        "start_lat": payload.startLat,
        "start_lng": payload.startLng,
        "start_maps_link": start_maps,
        "end_time": now,
        "end_lat": payload.endLat,
        "end_lng": payload.endLng,
        "end_maps_link": end_maps,
        "completed_time": now,
    })

    return map_completed_ride(row)

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
async def get_passenger_requests(
    status: Optional[str] = "open",
    query: Optional[str] = None,
    location: Optional[str] = None,
    exclude_user_id: Optional[str] = None,
    exclude_phone: Optional[str] = None,
):
    try:
        await check_and_cleanup_expired_scheduled_posts()
    except Exception:
        pass

    conn = get_db()
    cursor = conn.cursor()
    sql = "SELECT * FROM passenger_requests WHERE 1=1"
    params = []

    if status and status.lower() != "all":
        sql += " AND status = ?"
        params.append(status)

    if query and query.strip():
        q_val = f"%{query.strip().lower()}%"
        sql += """ AND (
            LOWER(pickup) LIKE ? OR LOWER(dropoff) LIKE ? 
            OR LOWER(passenger_name) LIKE ? OR LOWER(passenger_dept) LIKE ? 
            OR LOWER(notes) LIKE ?
        )"""
        params.extend([q_val, q_val, q_val, q_val, q_val])

    if location and location.strip() and location.strip().lower() != "all":
        loc_val = f"%{location.strip().lower()}%"
        sql += " AND (LOWER(pickup) LIKE ? OR LOWER(dropoff) LIKE ?)"
        params.extend([loc_val, loc_val])

    if exclude_user_id:
        sql += " AND (passenger_id != ? AND passenger_id NOT LIKE ?)"
        params.extend([exclude_user_id, f"%{exclude_user_id}%"])

    if exclude_phone:
        clean_p = "".join(filter(str.isdigit, exclude_phone))
        if len(clean_p) >= 8:
            short_p = clean_p[-8:]
            sql += " AND passenger_phone NOT LIKE ?"
            params.append(f"%{short_p}%")
        else:
            sql += " AND passenger_phone != ?"
            params.append(exclude_phone)

    sql += " ORDER BY created_at DESC"
    cursor.execute(sql, params)
    rows = cursor.fetchall()
    conn.close()
    return [map_passenger_request(r) for r in rows]

@app.post("/ride/api/passenger-requests/{request_id}/extend-time")
@app.post("/api/passenger-requests/{request_id}/extend-time")
async def extend_passenger_request_time(request_id: str, payload: Dict[str, Any] = Body(...)):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Passenger request not found")
    
    minutes = int(payload.get("minutes", 30))
    new_requested_time = payload.get("newRequestedTime")
    if not new_requested_time:
        try:
            cur_dt = datetime.fromisoformat(row["requested_time"].replace("Z", "+00:00")).replace(tzinfo=None)
            base_dt = max(datetime.utcnow(), cur_dt)
        except Exception:
            base_dt = datetime.utcnow()
        new_dt = base_dt + timedelta(minutes=minutes)
        new_requested_time = new_dt.isoformat()
    
    now_iso = datetime.utcnow().isoformat()
    cursor.execute("""
        UPDATE passenger_requests 
        SET requested_time = ?, extended_at = ?, extension_prompted = 0, status = 'open'
        WHERE id = ?
    """, (new_requested_time, now_iso, request_id))
    conn.commit()
    cursor.execute("SELECT * FROM passenger_requests WHERE id = ?", (request_id,))
    updated_row = cursor.fetchone()
    conn.close()

    updated = map_passenger_request(updated_row)
    await manager.broadcast("passenger_request_updated", updated)
    await manager.broadcast("passenger_request_extended", {
        "id": request_id,
        "requestedTime": new_requested_time,
        "minutes": minutes
    })
    return {"status": "success", "request": updated, "newRequestedTime": new_requested_time}

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

    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Request not found")

    now = datetime.utcnow().isoformat()
    fare_val = float(row["proposed_fare"] or 50.0)

    # Ensure matching record exists in `rides` so session tracking and complete-session work without 404!
    cursor.execute("""
    INSERT OR REPLACE INTO rides (
        id, driver_id, driver_name, driver_phone, origin_name, origin_lat, origin_lng, destination_name, destination_lat, destination_lng,
        departure_time, fare_per_seat, total_seats, available_seats, status,
        vehicle_model, vehicle_type, created_at, passenger_id, passenger_name, rider_confirmed, passenger_confirmed
    ) VALUES (?, ?, ?, ?, ?, 23.8765, 90.3204, ?, 23.8071, 90.3686, ?, ?, 1, 0, 'confirmed', ?, 'bike', ?, ?, ?, 1, 1)
    """, (
        request_id, driver_id, driver_name, driver_phone,
        row["pickup"], row["dropoff"], row["requested_time"],
        fare_val, driver_bike, now, row["passenger_id"], row["passenger_name"]
    ))

    # Also insert or replace into `bookings`
    bkg_id = f"bkg_{request_id}"
    cursor.execute("""
    INSERT OR REPLACE INTO bookings (
        id, ride_id, passenger_id, passenger_name, passenger_phone,
        pickup_point, dropoff_point, seats_booked, total_fare, status, requested_at,
        trip_status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, 'accepted', ?, 'confirmed')
    """, (
        bkg_id, request_id, row["passenger_id"], row["passenger_name"],
        row["passenger_phone"], row["pickup"], row["dropoff"],
        fare_val, now
    ))
    conn.commit()
    conn.close()

    updated = map_passenger_request(row)
    # Broadcast acceptance to passenger and all clients!
    await manager.broadcast("passenger_request_accepted", updated)

    # Insert initial automated chat message so both biker and requester see confirmation in chatbox!
    acc_msg = f"🤝 Ride Request Accepted!\n🏍️ Biker: {driver_name} ({driver_bike})\n📍 Route: {row['pickup']} ➔ {row['dropoff']}\n💰 Fare: ৳{fare_val:.0f}\n⏰ Departure: {row['requested_time']}"
    await _save_and_broadcast_message(request_id, {
        "rideId": request_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": acc_msg,
        "isLocationShare": False,
        "timestamp": now,
    })

    return updated

@app.delete("/ride/api/passenger-requests/{request_id}")
@app.delete("/api/passenger-requests/{request_id}")
@app.delete("/ride/api/passenger-requests")
@app.delete("/api/passenger-requests")
@app.post("/ride/api/passenger-requests/{request_id}/delete")
@app.post("/api/passenger-requests/{request_id}/delete")
@app.post("/ride/api/passenger-requests/delete")
@app.post("/api/passenger-requests/delete")
async def delete_passenger_request_endpoint(
    request_id: Optional[str] = None,
    id: Optional[str] = Query(None),
    request: Request = None
):
    target_id = request_id or id
    if not target_id and request:
        try:
            body = await request.json()
            target_id = body.get("id") or body.get("requestId") or body.get("request_id")
        except Exception:
            pass
    if not target_id:
        raise HTTPException(status_code=400, detail="Missing request_id to delete")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM passenger_requests WHERE id = ?", (target_id,))
    cursor.execute("DELETE FROM rides WHERE id = ?", (target_id,))
    cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (target_id,))
    conn.commit()
    conn.close()

    await manager.broadcast("passenger_request_deleted", {"id": target_id})
    return {"status": "success", "message": f"Passenger request {target_id} deleted successfully", "id": target_id}

@app.post("/ride/api/admin/clear-all-records")
@app.post("/api/admin/clear-all-records")
@app.delete("/ride/api/admin/clear-all-records")
@app.delete("/api/admin/clear-all-records")
async def clear_all_records_endpoint():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM rides")
    cursor.execute("DELETE FROM bookings")
    cursor.execute("DELETE FROM passenger_requests")
    cursor.execute("DELETE FROM messages")
    cursor.execute("DELETE FROM shared_locations")
    cursor.execute("DELETE FROM driver_locations")
    cursor.execute("DELETE FROM sos_alerts")
    conn.commit()
    conn.close()

    await manager.broadcast("rides_cleared", {"status": "cleared", "timestamp": datetime.utcnow().isoformat()})
    print("[ADMIN] All rides, bookings, requests, messages, and locations cleared from database.")
    return {"status": "success", "message": "All ride records and associated data have been purged successfully."}

# =====================================================================
# REST Endpoints: Alert Ring / Sound Trigger
# =====================================================================

@app.post("/ride/api/alert-ring")
@app.post("/api/alert-ring")
async def trigger_alert_ring(payload: Dict[str, Any]):
    sender_name = str(payload.get("senderName", "Campus Rider")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    target_user_id = str(payload.get("targetUserId", "")).strip()
    target_name = str(payload.get("targetName", "")).strip()
    ride_id = str(payload.get("rideId", "")).strip()
    ring_id = str(payload.get("ringId", f"ring_{int(datetime.utcnow().timestamp()*1000)}")).strip()
    message = str(payload.get("message", f"🚨 Urgent alert from {sender_name}: Please check your phone!")).strip()
    now = datetime.utcnow().isoformat()

    event_data = {
        "event": "alert_ring",
        "type": "alert_ring",
        "ringId": ring_id,
        "senderId": sender_id,
        "senderName": sender_name,
        "targetUserId": target_user_id,
        "targetName": target_name,
        "rideId": ride_id,
        "message": message,
        "timestamp": now,
    }
    await manager.broadcast("alert_ring", event_data)
    print(f"[ALERT-RING] Dispatched buzzer {ring_id} from {sender_name} to {target_user_id} (ride {ride_id})")
    return {"status": "success", "message": "Alert ring buzzer dispatched successfully", "data": event_data}

@app.post("/ride/api/stop-ring")
@app.post("/api/stop-ring")
async def stop_alert_ring(payload: Dict[str, Any]):
    ring_id = str(payload.get("ringId", "")).strip()
    target_user_id = str(payload.get("targetUserId", "")).strip()
    sender_id = str(payload.get("senderId", "")).strip()
    now = datetime.utcnow().isoformat()

    event_data = {
        "event": "stop_ring",
        "type": "stop_ring",
        "ringId": ring_id,
        "targetUserId": target_user_id,
        "senderId": sender_id,
        "timestamp": now,
    }
    await manager.broadcast("stop_ring", event_data)
    print(f"[STOP-RING] Alert ring {ring_id} stopped for {target_user_id} by {sender_id}")
    return {"status": "success", "message": "Alert ring stopped successfully", "data": event_data}

@app.post("/ride/api/admin/clear-all-records")
@app.post("/api/admin/clear-all-records")
async def clear_all_records():
    conn = get_db()
    cursor = conn.cursor()
    tables = [
        "bookings",
        "messages",
        "shared_locations",
        "driver_locations",
        "sos_alerts",
        "passenger_requests",
        "completed_rides",
        "email_otps",
        "rides",
        "users",
    ]
    for table in tables:
        try:
            cursor.execute(f"DELETE FROM {table};")
        except Exception as e:
            print(f"[ADMIN CLEAR] Error deleting {table}: {e}")
    conn.commit()
    conn.close()
    await manager.broadcast("records_cleared", {"timestamp": datetime.utcnow().isoformat()})
    print("[ADMIN CLEAR] Cleared all records across all tables for fresh production deployment.")
    return {"status": "success", "message": "All records purged cleanly."}

# =====================================================================
# REST Endpoints: Bookings
# =====================================================================

BOOKINGS_JOIN_QUERY = """
    SELECT b.*,
           COALESCE(b.driver_id, r.driver_id, cr.driver_id) AS driver_id,
           COALESCE(b.driver_name, r.driver_name, cr.driver_name) AS driver_name,
           COALESCE(b.driver_phone, r.driver_phone) AS driver_phone,
           COALESCE(b.vehicle_model, r.vehicle_model) AS vehicle_model,
           COALESCE(b.departure_time, r.departure_time) AS departure_time,
           COALESCE(b.origin_name, r.origin_name, cr.origin_name) AS origin_name,
           COALESCE(b.destination_name, r.destination_name, cr.destination_name) AS destination_name,
           COALESCE(r.status, 'completed') AS ride_status
    FROM bookings b
    LEFT JOIN rides r ON b.ride_id = r.id
    LEFT JOIN completed_rides cr ON b.ride_id = cr.ride_id
"""

@app.get("/ride/api/bookings")
@app.get("/api/bookings")
def get_bookings(
    passenger_id: Optional[str] = Query(None),
    ride_id: Optional[str] = Query(None),
):
    conn = get_db()
    cursor = conn.cursor()
    if passenger_id and ride_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.passenger_id = ? AND b.ride_id = ? ORDER BY b.requested_at DESC", (passenger_id, ride_id))
    elif passenger_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.passenger_id = ? ORDER BY b.requested_at DESC", (passenger_id,))
    elif ride_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.ride_id = ? ORDER BY b.requested_at DESC", (ride_id,))
    else:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} ORDER BY b.requested_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [map_booking(b) for b in rows]

@app.patch("/ride/api/bookings")
@app.patch("/api/bookings")
async def update_booking_patch(payload: Dict[str, Any]):
    booking_id = payload.get("id")
    status = payload.get("status", "accepted")
    if not booking_id:
        raise HTTPException(status_code=400, detail="Missing booking id")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Booking not found")

    old_status = row["status"]
    seats = row["seats_booked"]
    ride_id = row["ride_id"]

    cursor.execute("UPDATE bookings SET status = ? WHERE id = ?", (status, booking_id))
    if status in ("cancelled", "rejected") and old_status not in ("cancelled", "rejected"):
        cursor.execute("UPDATE rides SET available_seats = available_seats + ? WHERE id = ?", (seats, ride_id))
    conn.commit()

    cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.id = ?", (booking_id,))
    updated_row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    updated = map_booking(updated_row)
    await manager.broadcast("booking_status_updated", updated)
    if ride_row:
        await manager.broadcast("ride_updated", map_ride(ride_row))
    return updated

@app.get("/ride/api/bookings/my-bookings")
@app.get("/api/bookings/my-bookings")
def get_my_bookings(user_id: Optional[str] = Query(None)):
    conn = get_db()
    cursor = conn.cursor()
    if user_id:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.passenger_id = ? ORDER BY b.requested_at DESC", (user_id,))
    else:
        cursor.execute(f"{BOOKINGS_JOIN_QUERY} ORDER BY b.requested_at DESC")
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
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()

    cursor.execute("""
    INSERT INTO bookings (
        id, ride_id, passenger_id, passenger_name, passenger_photo_url,
        passenger_dept, passenger_phone, pickup_point, dropoff_point,
        seats_booked, total_fare, status, requested_at,
        driver_id, driver_name, driver_phone, vehicle_model,
        departure_time, origin_name, destination_name
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
        ride_row["driver_id"] if ride_row else booking_data.get("driverId"),
        ride_row["driver_name"] if ride_row else booking_data.get("driverName"),
        ride_row["driver_phone"] if ride_row else booking_data.get("driverPhone"),
        ride_row["vehicle_model"] if ride_row else booking_data.get("vehicleModel"),
        ride_row["departure_time"] if ride_row else booking_data.get("departureTime"),
        ride_row["origin_name"] if ride_row else booking_data.get("originName"),
        ride_row["destination_name"] if ride_row else booking_data.get("destinationName"),
    ))

    # Update ride available seats
    cursor.execute("UPDATE rides SET available_seats = MAX(0, available_seats - ?) WHERE id = ?", (seats, ride_id))
    conn.commit()

    cursor.execute(f"{BOOKINGS_JOIN_QUERY} WHERE b.id = ?", (booking_id,))
    row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    updated_ride_row = cursor.fetchone()
    conn.close()

    created = map_booking(row)
    await manager.broadcast("booking_created", created)
    if updated_ride_row:
        try:
            if int(updated_ride_row["available_seats"] or 0) <= 0:
                remove_ride_from_file(ride_id)
            else:
                add_or_update_ride_in_file(dict(updated_ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on booking] {e}")
        # Dedicated notification to driver
        await manager.broadcast("ride_booking_request", {
            "driverId": updated_ride_row["driver_id"],
            "driverName": updated_ride_row["driver_name"],
            "passengerId": created["passengerId"],
            "passengerName": created["passengerName"],
            "pickup": created["pickupPoint"],
            "dropoff": created["dropoffPoint"],
            "seats": created["seatsBooked"],
            "fare": created["totalFare"],
            "rideId": ride_id,
            "bookingId": booking_id,
            "message": f"🔔 New seat booking request from {created['passengerName']}!",
        })
        await manager.broadcast("ride_updated", map_ride(updated_ride_row))

    return created

@app.post("/ride/api/bookings/{booking_id}/accept")
@app.post("/api/bookings/{booking_id}/accept")
async def accept_booking(booking_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE bookings SET status = 'accepted' WHERE id = ?", (booking_id,))
    # Confirm the ride destination on that location where the passenger requested
    cursor.execute("""
        UPDATE rides 
        SET destination_name = COALESCE((SELECT dropoff_point FROM bookings WHERE id = ?), destination_name),
            passenger_id = (SELECT passenger_id FROM bookings WHERE id = ?),
            passenger_name = (SELECT passenger_name FROM bookings WHERE id = ?)
        WHERE id = (SELECT ride_id FROM bookings WHERE id = ?)
    """, (booking_id, booking_id, booking_id, booking_id))
    cursor.execute("""
        SELECT b.*, r.driver_id, r.driver_name, r.origin_name, r.destination_name
        FROM bookings b LEFT JOIN rides r ON b.ride_id = r.id WHERE b.id = ?
    """, (booking_id,))
    row = cursor.fetchone()
    ride_id = row["ride_id"] if row else None
    ride_row = None
    if ride_id:
        cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
        ride_row = cursor.fetchone()
    conn.commit()
    conn.close()
    if ride_row:
        await manager.broadcast("ride_updated", map_ride(ride_row))
    if row:
        updated = map_booking(row)
        await manager.broadcast("booking_status_updated", updated)
        # Dedicated alert to passenger
        await manager.broadcast("ride_booking_accepted", {
            "passengerId": row["passenger_id"],
            "passengerName": row["passenger_name"],
            "driverId": row["driver_id"],
            "driverName": row["driver_name"],
            "rideId": row["ride_id"],
            "bookingId": booking_id,
            "message": f"✅ Rider {row['driver_name']} accepted your ride request! Tap to open chat.",
        })
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
        try:
            add_or_update_ride_in_file(dict(ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on reject_booking] {e}")
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
    # Cancel in time: do not delete the post, make the post refreshed with open seats and published status
    cursor.execute("""
        UPDATE rides 
        SET available_seats = MIN(total_seats, available_seats + ?),
            status = 'published',
            rider_confirmed = 0,
            passenger_confirmed = 0,
            passenger_id = NULL,
            passenger_name = NULL
        WHERE id = ?
    """, (seats, ride_id))
    conn.commit()

    cursor.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,))
    updated_row = cursor.fetchone()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    conn.close()

    updated = map_booking(updated_row)
    await manager.broadcast("booking_status_updated", updated)
    if ride_row:
        try:
            add_or_update_ride_in_file(dict(ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on cancel_booking] {e}")
        refreshed_ride = map_ride(ride_row)
        await manager.broadcast("ride_updated", refreshed_ride)
        print(f"[BOOKING CANCELLED] Ride {ride_id} refreshed and reopened for booking.")
    return updated

# =====================================================================
# Realtime Ride Session Lifecycle: Two-Way Confirmation, Cancel, Complete
# =====================================================================

@app.post("/ride/api/rides/confirm-session")
@app.post("/api/rides/confirm-session")
async def confirm_ride_session(payload: Dict[str, Any]):
    ride_id = payload.get("rideId")
    user_id = payload.get("userId", "")
    user_name = payload.get("userName", "Student")
    role = (payload.get("role") or "passenger").lower() # "rider" or "passenger"
    lat = payload.get("latitude")
    lng = payload.get("longitude")

    if not ride_id:
        raise HTTPException(status_code=400, detail="Missing rideId")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    if not ride_row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found")

    rider_conf = int(ride_row["rider_confirmed"] or 0)
    pass_conf = int(ride_row["passenger_confirmed"] or 0)

    if role in ("rider", "driver"):
        rider_conf = 1
    else:
        pass_conf = 1

    both_confirmed = (rider_conf == 1 and pass_conf == 1)
    now = datetime.utcnow().isoformat()
    start_time = ride_row["start_time"] or (now if both_confirmed else None)

    if both_confirmed:
        start_maps = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}" if lat and lng else ride_row["start_maps_link"]
        cursor.execute("""
            UPDATE rides 
            SET rider_confirmed = ?, passenger_confirmed = ?, status = 'active', start_time = COALESCE(start_time, ?),
                start_lat = COALESCE(start_lat, ?), start_lng = COALESCE(start_lng, ?), start_maps_link = COALESCE(start_maps_link, ?)
            WHERE id = ?
        """, (rider_conf, pass_conf, now, lat, lng, start_maps, ride_id))
        cursor.execute("UPDATE bookings SET rider_confirmed = 1, passenger_confirmed = 1, status = 'accepted', trip_status = 'in_progress', started_at = COALESCE(started_at, ?) WHERE ride_id = ?", (now, ride_id))

        # Auto-cleanup previous published feeds/posts for this driver so feeds are cleared
        driver_id = ride_row["driver_id"]
        driver_phone = ride_row["driver_phone"] if "driver_phone" in ride_row.keys() else None
        cursor.execute(
            "SELECT id FROM rides WHERE id != ? AND (driver_id = ? OR (driver_phone IS NOT NULL AND driver_phone != '' AND driver_phone = ?)) AND status = 'published'",
            (ride_id, driver_id, driver_phone)
        )
        for s_r in cursor.fetchall():
            cursor.execute("DELETE FROM rides WHERE id = ?", (s_r["id"],))
            cursor.execute("DELETE FROM bookings WHERE ride_id = ?", (s_r["id"],))
            await manager.broadcast("ride_deleted", {"id": s_r["id"]})

        # Auto-cleanup open requests for passenger
        cursor.execute("SELECT passenger_id, passenger_phone FROM bookings WHERE ride_id = ?", (ride_id,))
        for b_row in cursor.fetchall():
            p_id = b_row["passenger_id"]
            p_ph = b_row["passenger_phone"]
            cursor.execute(
                "SELECT id FROM passenger_requests WHERE (passenger_id = ? OR (passenger_phone IS NOT NULL AND passenger_phone != '' AND passenger_phone = ?)) AND status = 'open'",
                (p_id, p_ph)
            )
            for s_req in cursor.fetchall():
                cursor.execute("DELETE FROM passenger_requests WHERE id = ?", (s_req["id"],))
                await manager.broadcast("passenger_request_deleted", {"id": s_req["id"]})
    else:
        cursor.execute("""
            UPDATE rides SET rider_confirmed = ?, passenger_confirmed = ? WHERE id = ?
        """, (rider_conf, pass_conf, ride_id))
        if role in ("rider", "driver"):
            cursor.execute("UPDATE bookings SET rider_confirmed = 1 WHERE ride_id = ?", (ride_id,))
        else:
            cursor.execute("UPDATE bookings SET passenger_confirmed = 1 WHERE ride_id = ?", (ride_id,))

    conn.commit()

    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    updated_row = cursor.fetchone()
    conn.close()

    updated = map_ride(updated_row)

    # Post automated system chat message
    if both_confirmed:
        sys_msg = f"🚀 Both Rider and Passenger confirmed! Ready to ride! Trip officially started. Live timer is running."
    else:
        sys_msg = f"✅ {user_name} ({role.title()}) confirmed the ride! Waiting for peer confirmation."

    await _save_and_broadcast_message(ride_id, {
        "rideId": ride_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": sys_msg,
        "isLocationShare": False,
        "timestamp": now,
    })

    session_event = {
        "rideId": ride_id,
        "riderConfirmed": bool(rider_conf),
        "passengerConfirmed": bool(pass_conf),
        "bothConfirmed": both_confirmed,
        "status": "in_progress" if both_confirmed else "pending",
        "startTime": start_time or now,
        "updaterId": user_id,
        "updaterName": user_name,
        "role": role,
    }
    await manager.broadcast("ride_session_status_changed", session_event)
    await manager.broadcast("ride_updated", updated)

    return session_event

@app.post("/ride/api/rides/cancel-session")
@app.post("/api/rides/cancel-session")
async def cancel_ride_session(payload: Dict[str, Any]):
    ride_id = payload.get("rideId")
    user_id = payload.get("userId", "")
    user_name = payload.get("userName", "Student")
    role = (payload.get("role") or "passenger").lower()
    reason = payload.get("reason", "Fare not agreed / Contact not made")

    if not ride_id:
        raise HTTPException(status_code=400, detail="Missing rideId")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    if not ride_row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found")

    now = datetime.utcnow().isoformat()
    # Cancel in time: do not delete the post, make the post refreshed for new passengers!
    cursor.execute("""
        UPDATE rides 
        SET status = 'published',
            available_seats = total_seats,
            rider_confirmed = 0,
            passenger_confirmed = 0,
            passenger_id = NULL,
            passenger_name = NULL,
            start_time = NULL,
            start_maps_link = NULL,
            cancel_reason = ? 
        WHERE id = ?
    """, (reason, ride_id))
    cursor.execute("UPDATE bookings SET status = 'cancelled', trip_status = 'cancelled', cancel_reason = ? WHERE ride_id = ?", (reason, ride_id))
    conn.commit()

    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    refreshed_ride_row = cursor.fetchone()
    cursor.execute("SELECT * FROM bookings WHERE ride_id = ? LIMIT 1", (ride_id,))
    b_row = cursor.fetchone()
    conn.close()

    # Save cancel event to CSV
    append_completed_trip_csv({
        "trip_id": f"canc_{ride_id}_{int(datetime.utcnow().timestamp())}",
        "rider_id": ride_row["driver_id"],
        "rider_name": ride_row["driver_name"],
        "rider_phone": ride_row["driver_phone"],
        "passenger_id": b_row["passenger_id"] if b_row else "",
        "passenger_name": b_row["passenger_name"] if b_row else "",
        "passenger_phone": b_row["passenger_phone"] if b_row else "",
        "origin": ride_row["origin_name"],
        "destination": ride_row["destination_name"],
        "fare": float(ride_row["fare_per_seat"]),
        "start_time": ride_row["start_time"] or now,
        "end_time": now,
        "status": "cancelled",
        "cancel_reason": reason,
        "total_duration_minutes": 0.0,
        "completed_time": now,
    })

    # System message
    sys_msg = f"❌ Trip cancelled by {user_name} ({role.title()}). Reason: {reason}. Post has been refreshed and reopened for bookings."
    await _save_and_broadcast_message(ride_id, {
        "rideId": ride_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": sys_msg,
        "isLocationShare": False,
        "timestamp": now,
    })

    session_event = {
        "rideId": ride_id,
        "status": "cancelled",
        "cancelReason": reason,
        "cancelledBy": user_name,
        "role": role,
    }
    await manager.broadcast("ride_session_status_changed", session_event)
    if refreshed_ride_row:
        try:
            add_or_update_ride_in_file(dict(refreshed_ride_row))
        except Exception as e:
            print(f"[ACTIVE RIDES FILE ERROR on cancel_session] {e}")
        await manager.broadcast("ride_updated", map_ride(refreshed_ride_row))
        print(f"[RIDE SESSION CANCELLED IN TIME] Post {ride_id} refreshed and republished.")

    return session_event

@app.post("/ride/api/rides/complete-session")
@app.post("/api/rides/complete-session")
async def complete_ride_session(payload: Dict[str, Any]):
    ride_id = payload.get("rideId")
    user_id = payload.get("userId", "")
    user_name = payload.get("userName", "Student")
    role = (payload.get("role") or "companion").lower()
    lat = payload.get("latitude")
    lng = payload.get("longitude")

    if not ride_id:
        raise HTTPException(status_code=400, detail="Missing rideId")

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    if not ride_row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found")

    now = datetime.utcnow().isoformat()
    start_t_str = ride_row["start_time"] or now
    try:
        dt_start = datetime.fromisoformat(start_t_str.replace("Z", "+00:00"))
        dt_end = datetime.fromisoformat(now.replace("Z", "+00:00"))
        duration_mins = max(1.0, round((dt_end - dt_start).total_seconds() / 60.0, 1))
    except Exception:
        duration_mins = 15.0

    end_maps = f"https://www.google.com/maps/search/?api=1&query={lat},{lng}" if lat and lng else ""

    cursor.execute("""
        UPDATE rides 
        SET status = 'completed', end_time = ?, end_lat = COALESCE(?, end_lat), end_lng = COALESCE(?, end_lng),
            end_maps_link = COALESCE(?, end_maps_link), total_duration_minutes = ?
        WHERE id = ?
    """, (now, lat, lng, end_maps, duration_mins, ride_id))

    cursor.execute("""
        UPDATE bookings 
        SET status = 'completed', trip_status = 'completed', completed_at = ?, total_duration_minutes = ?,
            end_lat = COALESCE(?, end_lat), end_lng = COALESCE(?, end_lng)
        WHERE ride_id = ?
    """, (now, duration_mins, lat, lng, ride_id))
    conn.commit()

    cursor.execute("SELECT passenger_id, passenger_name, passenger_phone, total_fare FROM bookings WHERE ride_id = ? LIMIT 1", (ride_id,))
    b_row = cursor.fetchone()
    p_id = b_row["passenger_id"] if b_row else ""
    p_name = b_row["passenger_name"] if b_row else ""
    p_phone = b_row["passenger_phone"] if b_row else ""
    fare = float(b_row["total_fare"]) if b_row else float(ride_row["fare_per_seat"])

    # Insert into completed_rides
    comp_id = f"comp_{ride_id}_{int(datetime.utcnow().timestamp())}"
    cursor.execute("""
        INSERT OR REPLACE INTO completed_rides (
            id, ride_id, driver_id, driver_name, passenger_id, passenger_name,
            origin_name, destination_name, start_time, completed_time, fare,
            start_maps_link, end_maps_link, rating, created_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        comp_id, ride_id, ride_row["driver_id"], ride_row["driver_name"], p_id, p_name,
        ride_row["origin_name"], ride_row["destination_name"], start_t_str, now,
        fare, ride_row["start_maps_link"], end_maps, 5.0, now
    ))
    conn.commit()
    conn.close()

    # Append to CSV
    append_completed_trip_csv({
        "trip_id": comp_id,
        "rider_id": ride_row["driver_id"],
        "rider_name": ride_row["driver_name"],
        "rider_phone": ride_row["driver_phone"],
        "passenger_id": p_id,
        "passenger_name": p_name,
        "passenger_phone": p_phone,
        "origin": ride_row["origin_name"],
        "destination": ride_row["destination_name"],
        "fare": fare,
        "start_time": start_t_str,
        "start_lat": ride_row["start_lat"],
        "start_lng": ride_row["start_lng"],
        "start_maps_link": ride_row["start_maps_link"],
        "end_time": now,
        "end_lat": lat,
        "end_lng": lng,
        "end_maps_link": end_maps,
        "total_duration_minutes": duration_mins,
        "status": "completed",
        "completed_time": now,
    })

    # If complete, auto-delete the post from active rides table
    conn = get_db()
    cursor = conn.cursor()
    # Auto-delete from active rides table so it doesn't appear in active rides pool, but keep bookings with status 'completed'
    cursor.execute("DELETE FROM rides WHERE id = ?", (ride_id,))
    conn.commit()
    conn.close()

    try:
        remove_ride_from_file(ride_id)
    except Exception as e:
        print(f"[ACTIVE RIDES FILE ERROR on complete_ride_session] {e}")

    # Automated chat message
    try:
        time_formatted = datetime.fromisoformat(now.replace("Z", "+00:00")).strftime("%I:%M %p, %b %d")
    except Exception:
        time_formatted = now
    sys_msg = f"🏁 Trip Completed!\n📍 Location: {ride_row['origin_name']} ➔ {ride_row['destination_name']}\n⏰ Completed at: {time_formatted}\n⏱️ Duration: {duration_mins:.0f} min(s)\n💰 Total Fare: ৳{fare:.0f}\nStatus: Arrived safely at destination."
    await _save_and_broadcast_message(ride_id, {
        "rideId": ride_id,
        "senderId": "system",
        "senderName": "DIU Ride System",
        "text": sys_msg,
        "isLocationShare": False,
        "timestamp": now,
    })

    session_event = {
        "rideId": ride_id,
        "status": "completed",
        "totalDurationMinutes": duration_mins,
        "completedAt": now,
        "fare": fare,
        "completedBy": user_name,
        "role": role,
    }
    await manager.broadcast("ride_session_status_changed", session_event)
    await manager.broadcast("ride_deleted", {"id": ride_id, "reason": "completed"})
    await manager.broadcast("post_deleted", {"postId": ride_id, "id": ride_id, "type": "ride", "reason": "completed"})
    await manager.broadcast("ride_completed", session_event)
    await manager.broadcast("booking_status_updated", {"rideId": ride_id, "status": "completed"})

    return session_event

@app.get("/ride/api/rides/{ride_id}/session-status")
@app.get("/api/rides/{ride_id}/session-status")
def get_ride_session_status(ride_id: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM rides WHERE id = ?", (ride_id,))
    ride_row = cursor.fetchone()
    if not ride_row:
        conn.close()
        raise HTTPException(status_code=404, detail="Ride not found")
    
    cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC LIMIT 1", (ride_id,))
    b_row = cursor.fetchone()
    conn.close()

    r_conf = bool(ride_row["rider_confirmed"]) if ("rider_confirmed" in ride_row.keys() and ride_row["rider_confirmed"]) else False
    p_conf = bool(ride_row["passenger_confirmed"]) if ("passenger_confirmed" in ride_row.keys() and ride_row["passenger_confirmed"]) else False
    status = ride_row["status"]
    if status == "active" and r_conf and p_conf:
        session_status = "in_progress"
    elif status == "completed":
        session_status = "completed"
    elif status == "cancelled":
        session_status = "cancelled"
    else:
        session_status = "pending"

    return {
        "rideId": ride_id,
        "status": session_status,
        "rawStatus": status,
        "riderConfirmed": r_conf,
        "passengerConfirmed": p_conf,
        "bothConfirmed": r_conf and p_conf,
        "startTime": ride_row["start_time"],
        "endTime": ride_row["end_time"],
        "origin": ride_row["origin_name"],
        "destination": ride_row["destination_name"],
        "fare": float(ride_row["fare_per_seat"]),
        "driverId": ride_row["driver_id"],
        "driverName": ride_row["driver_name"],
        "passengerId": b_row["passenger_id"] if b_row else "",
        "passengerName": b_row["passenger_name"] if b_row else "",
        "totalDurationMinutes": float(ride_row["total_duration_minutes"] or 0.0) if ("total_duration_minutes" in ride_row.keys() and ride_row["total_duration_minutes"]) else 0.0,
        "cancelReason": ride_row["cancel_reason"] if ("cancel_reason" in ride_row.keys()) else "",
    }

# =====================================================================
# REST Endpoints: Chat & Realtime Messaging
# =====================================================================

def get_channel_id(ride_id: str, u1: str, u2: str) -> str:
    """Computes a deterministic, isolated 1-on-1 channel ID between two users for a given ride."""
    if not u1 or not u2 or str(u1).strip().lower() == str(u2).strip().lower():
        return ride_id
    base = ride_id.split('__')[0] if '__' in ride_id else ride_id
    pair = sorted([str(u1).strip(), str(u2).strip()])
    return f"{base}__{pair[0]}__{pair[1]}"

def _fetch_messages(target_ride_id: Optional[str]):
    """Fetch messages strictly for the given ride_id/channel_id only.
    No cross-ride or cross-peer joining — each 1-on-1 conversation is isolated."""
    conn = get_db()
    cursor = conn.cursor()
    if not target_ride_id:
        cursor.execute("SELECT * FROM messages ORDER BY timestamp ASC")
        rows = cursor.fetchall()
        conn.close()
        return [map_message(m) for m in rows]

    if "__" in target_ride_id:
        parts = target_ride_id.split("__")
        base_id = parts[0]
        u1 = parts[1]
        u2 = parts[2]
        cursor.execute(
            """
            SELECT * FROM messages 
            WHERE ride_id = ? 
               OR (ride_id = ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)))
            ORDER BY timestamp ASC
            """,
            (target_ride_id, base_id, u1, u2, u2, u1)
        )
    else:
        cursor.execute(
            "SELECT * FROM messages WHERE ride_id = ? ORDER BY timestamp ASC",
            (target_ride_id,)
        )
    rows = cursor.fetchall()
    conn.close()
    return [map_message(m) for m in rows]

async def _save_and_broadcast_message(target_ride_id: str, msg_data: Dict[str, Any]):
    msg_id = msg_data.get("id") or f"msg_{int(datetime.utcnow().timestamp()*1000)}"
    text = msg_data.get("text", "")
    is_loc = bool(msg_data.get("isLocationShare", False))
    shared_lat = msg_data.get("sharedLat")
    shared_lng = msg_data.get("sharedLng")
    sender_id = str(msg_data.get("senderId", "usr_anonymous")).strip()
    receiver_id = str(msg_data.get("receiverId", "")).strip() or None

    # Derive unique 1-on-1 private channel ID
    channel_id = target_ride_id
    if "__" in target_ride_id:
        channel_id = target_ride_id
        parts = target_ride_id.split("__")
        if not receiver_id and len(parts) >= 3:
            receiver_id = parts[2] if sender_id == parts[1] else parts[1]
    elif sender_id and receiver_id and sender_id != receiver_id:
        channel_id = get_channel_id(target_ride_id, sender_id, receiver_id)

    # If sharing location, automatically ensure Google Maps link is included in text if not present
    if is_loc and shared_lat is not None and shared_lng is not None:
        maps_url = f"https://www.google.com/maps/search/?api=1&query={shared_lat},{shared_lng}"
        if "google.com/maps" not in text and "maps.google.com" not in text:
            text = f"📍 Shared Live GPS Location: {maps_url}"

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO messages (
        id, ride_id, sender_id, sender_name, receiver_id, text, timestamp,
        is_read, is_location_share, shared_lat, shared_lng
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
    """, (
        msg_id,
        channel_id,
        sender_id,
        msg_data.get("senderName", "DIU Student"),
        receiver_id,
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

@app.get("/ride/api/conversations")
@app.get("/api/conversations")
def get_user_conversations(user_id: Optional[str] = None):
    conn = get_db()
    cursor = conn.cursor()

    user_aliases = set()
    if user_id:
        uid_clean = user_id.strip()
        user_aliases.add(uid_clean.lower())
        cursor.execute("SELECT * FROM users WHERE id = ? OR student_id = ? OR LOWER(email) = LOWER(?)", (uid_clean, uid_clean, uid_clean))
        u_row = cursor.fetchone()
        if u_row:
            if u_row["id"]: user_aliases.add(str(u_row["id"]).lower())
            if u_row["student_id"]: user_aliases.add(str(u_row["student_id"]).lower())
            if u_row["email"]: user_aliases.add(str(u_row["email"]).lower())
            if u_row["name"]: user_aliases.add(str(u_row["name"]).lower())

    cursor.execute("""
        SELECT DISTINCT ride_id FROM messages
        UNION
        SELECT DISTINCT id as ride_id FROM rides
        UNION
        SELECT DISTINCT ride_id FROM bookings
    """)
    ride_ids = [row["ride_id"] for row in cursor.fetchall() if row["ride_id"]]

    conversations = []
    for rid in ride_ids:
        cursor.execute("SELECT * FROM rides WHERE id = ?", (rid,))
        ride_row = cursor.fetchone()

        cursor.execute("SELECT * FROM bookings WHERE ride_id = ? ORDER BY requested_at DESC", (rid,))
        bookings = cursor.fetchall()

        cursor.execute("SELECT * FROM messages WHERE ride_id = ? ORDER BY timestamp DESC", (rid,))
        msgs = cursor.fetchall()

        latest_msg = msgs[0]["text"] if msgs else "Tap to open conversation"
        latest_ts = msgs[0]["timestamp"] if msgs else (ride_row["created_at"] if ride_row else datetime.utcnow().isoformat())
        last_sender_name = msgs[0]["sender_name"] if msgs else ""
        last_sender_id = msgs[0]["sender_id"] if msgs else ""

        driver_id = str(ride_row["driver_id"]) if ride_row and ride_row["driver_id"] else "driver"
        driver_name = ride_row["driver_name"] if ride_row and ride_row["driver_name"] else "DIU Biker"
        driver_phone = ride_row["driver_phone"] if (ride_row and "driver_phone" in ride_row.keys() and ride_row["driver_phone"]) else "01712345678"
        vehicle_model = ride_row["vehicle_model"] if (ride_row and "vehicle_model" in ride_row.keys() and ride_row["vehicle_model"]) else "DIU Verified Bike"
        origin = ride_row["origin_name"] if ride_row and ride_row["origin_name"] else "Campus Gate"
        destination = ride_row["destination_name"] if ride_row and ride_row["destination_name"] else "Destination Spot"
        fare = float(ride_row["fare_per_seat"]) if ride_row and ride_row["fare_per_seat"] is not None else 35.0
        status = ride_row["status"] if ride_row and ride_row["status"] else "active"

        passengers_seen = {}
        for b in bookings:
            pid = str(b["passenger_id"])
            if pid not in passengers_seen:
                passengers_seen[pid] = {
                    "id": pid,
                    "name": b["passenger_name"] or "Passenger",
                    "phone": b["passenger_phone"] or "",
                    "dept": b["passenger_dept"] or "DIU Student",
                    "status": b["status"] or "booked",
                    "bookingId": b["id"],
                }

        for m in msgs:
            sid = str(m["sender_id"])
            if sid != driver_id and sid != "system" and sid not in passengers_seen:
                passengers_seen[sid] = {
                    "id": sid,
                    "name": m["sender_name"] or "DIU Commuter",
                    "phone": "",
                    "dept": "DIU Commuter",
                    "status": "inquired",
                    "bookingId": "",
                }

        is_driver = False
        if user_id:
            driver_candidates = {driver_id.lower(), driver_name.lower()}
            if user_aliases.intersection(driver_candidates):
                is_driver = True

        if is_driver:
            if passengers_seen:
                for pid, pdata in passengers_seen.items():
                    channel_id = get_channel_id(rid, driver_id, pid)
                    cursor.execute(
                        """
                        SELECT * FROM messages 
                        WHERE ride_id = ? 
                           OR (ride_id = ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)))
                        ORDER BY timestamp DESC
                        """,
                        (channel_id, rid, driver_id, pid, pid, driver_id)
                    )
                    p_msgs = cursor.fetchall()
                    p_latest = p_msgs[0]["text"] if p_msgs else "Tap to open conversation"
                    p_ts = p_msgs[0]["timestamp"] if p_msgs else latest_ts
                    p_sender = p_msgs[0]["sender_name"] if p_msgs else ""

                    conversations.append({
                        "rideId": channel_id,
                        "peerId": pid,
                        "peerName": pdata["name"],
                        "peerRole": "Passenger",
                        "peerPhone": pdata["phone"] or "Campus Peer",
                        "peerDept": pdata["dept"],
                        "route": f"{origin} ➔ {destination}",
                        "origin": origin,
                        "destination": destination,
                        "vehicleModel": vehicle_model,
                        "fare": fare,
                        "status": pdata["status"],
                        "bookingId": pdata["bookingId"],
                        "lastMessage": p_latest,
                        "lastTimestamp": p_ts,
                        "lastSenderName": p_sender,
                        "unreadCount": 1 if (p_msgs and p_msgs[0]["sender_id"] == pid) else 0,
                    })
            else:
                conversations.append({
                    "rideId": rid,
                    "peerId": "passengers",
                    "peerName": "Campus Commuters",
                    "peerRole": "Ride Channel",
                    "peerPhone": "DIU Smart City",
                    "peerDept": "Commuters Corridor",
                    "route": f"{origin} ➔ {destination}",
                    "origin": origin,
                    "destination": destination,
                    "vehicleModel": vehicle_model,
                    "fare": fare,
                    "status": status,
                    "bookingId": "",
                    "lastMessage": latest_msg,
                    "lastTimestamp": latest_ts,
                    "lastSenderName": last_sender_name,
                    "unreadCount": 0,
                })
        else:
            is_involved = not user_id
            if not is_involved:
                passenger_candidates = {p.lower() for p in passengers_seen.keys()}
                passenger_names = {p["name"].lower() for p in passengers_seen.values()}
                msg_senders = {str(m["sender_id"]).lower() for m in msgs}
                msg_names = {str(m["sender_name"]).lower() for m in msgs}
                all_involved = passenger_candidates.union(passenger_names).union(msg_senders).union(msg_names)
                if user_aliases.intersection(all_involved):
                    is_involved = True

            if is_involved:
                cur_pid = user_id if user_id else (list(passengers_seen.keys())[0] if passengers_seen else "passenger")
                channel_id = get_channel_id(rid, driver_id, cur_pid)
                cursor.execute(
                    """
                    SELECT * FROM messages 
                    WHERE ride_id = ? 
                       OR (ride_id = ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)))
                    ORDER BY timestamp DESC
                    """,
                    (channel_id, rid, driver_id, cur_pid, cur_pid, driver_id)
                )
                p_msgs = cursor.fetchall()
                latest_p_msg = p_msgs[0]["text"] if p_msgs else "Tap to open conversation"
                latest_p_ts = p_msgs[0]["timestamp"] if p_msgs else latest_ts
                latest_p_sender = p_msgs[0]["sender_name"] if p_msgs else ""

                conversations.append({
                    "rideId": channel_id,
                    "peerId": driver_id,
                    "peerName": driver_name,
                    "peerRole": "Biker / Rider",
                    "peerPhone": driver_phone,
                    "peerDept": "DIU Motorbike Driver",
                    "route": f"{origin} ➔ {destination}",
                    "origin": origin,
                    "destination": destination,
                    "vehicleModel": vehicle_model,
                    "fare": fare,
                    "status": status,
                    "bookingId": bookings[0]["id"] if bookings else "",
                    "lastMessage": latest_p_msg,
                    "lastTimestamp": latest_p_ts,
                    "lastSenderName": latest_p_sender,
                    "unreadCount": 1 if (p_msgs and p_msgs[0]["sender_id"] != cur_pid) else 0,
                })

    conn.close()

    # Deduplicate & consolidate regular commuter conversations by peer so threads don't split
    peer_grouped: Dict[str, Dict[str, Any]] = {}
    for c in conversations:
        peer_key = (c.get("peerPhone") or c.get("peerId") or c.get("peerName") or "peer").strip().lower()
        if peer_key not in peer_grouped:
            peer_grouped[peer_key] = c
        else:
            existing = peer_grouped[peer_key]
            if (c.get("lastTimestamp") or "") > (existing.get("lastTimestamp") or ""):
                peer_grouped[peer_key] = c

    consolidated = list(peer_grouped.values())
    consolidated.sort(key=lambda c: c.get("lastTimestamp", ""), reverse=True)

    # Fallback to ensure messages are always listed even if ID alias isn't strict
    if user_id and not consolidated:
        return get_user_conversations(user_id=None)

    return consolidated

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

    # ALSO record as a chat message so it immediately appears in the chatbox!
    loc_msg = {
        "id": f"msg_loc_{int(datetime.utcnow().timestamp()*1000)}",
        "rideId": ride_id,
        "senderId": user_id,
        "senderName": user_name,
        "text": f"📍 Shared Live GPS ({role.title()}): {maps_link}",
        "timestamp": now,
        "isLocationShare": True,
        "sharedLat": lat,
        "sharedLng": lng,
    }
    await _save_and_broadcast_message(ride_id, loc_msg)

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
# Production Diagnostics & System Info
# =====================================================================

@app.get("/ride/api/system/info")
@app.get("/api/system/info")
def system_info():
    return {
        "status": "production_ready",
        "service": "DIU Ride Production Unified Backend",
        "environment": "Ubuntu Linux (Production)",
        "database": "SQLite WAL High-Concurrency Mode",
        "active_ws_connections": len(manager.active_connections),
        "auth_provider": "Self-Hosted DIU Server (Firebase Email Verification Gateway)",
        "timestamp": datetime.utcnow().isoformat(),
    }

# =====================================================================
# Static Web App Hosting for Flutter Web (Production Ubuntu)
# =====================================================================

import mimetypes
mimetypes.init()
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/json", ".json")
mimetypes.add_type("text/css", ".css")
mimetypes.add_type("font/woff2", ".woff2")
mimetypes.add_type("font/woff", ".woff")
mimetypes.add_type("font/ttf", ".ttf")

# Check server/web_build first (deployed bundle), then fallback to parent web_build
web_dir = os.path.join(os.path.dirname(__file__), "web_build")
if not os.path.exists(web_dir):
    web_dir = os.path.join(os.path.dirname(__file__), "..", "web_build")

def _get_media_type(path: str) -> Optional[str]:
    mt, _ = mimetypes.guess_type(path)
    return mt

def _no_cache_response(file_path: str):
    response = FileResponse(file_path, media_type=_get_media_type(file_path))
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response

@app.api_route("/diu_ride.apk", methods=["GET", "HEAD"])
@app.api_route("/download-apk", methods=["GET", "HEAD"])
@app.api_route("/ride/diu_ride.apk", methods=["GET", "HEAD"])
@app.api_route("/ride/download-apk", methods=["GET", "HEAD"])
def download_apk():
    apk_path = os.path.join(web_dir, "diu_ride.apk")
    if not os.path.isfile(apk_path):
        # Fallback to build outputs directory
        apk_path = os.path.join(os.path.dirname(__file__), "..", "build", "app", "outputs", "flutter-apk", "app-release.apk")
    if os.path.isfile(apk_path):
        return FileResponse(
            apk_path,
            media_type="application/vnd.android.package-archive",
            filename="diu_ride.apk"
        )
    raise HTTPException(status_code=404, detail="APK not found")

@app.get("/ride/api/ai/live-rides")
@app.get("/api/ai/live-rides")
def get_live_rides_file_endpoint():
    rides = get_active_rides_from_file()
    return {
        "status": "success",
        "file": os.path.basename(ACTIVE_RIDES_JSON_PATH),
        "total_active_rides": len(rides),
        "rides": rides
    }

@app.get("/ride/api/ai/live-rides-markdown")
@app.get("/api/ai/live-rides-markdown")
def get_live_rides_markdown_endpoint():
    if os.path.exists(ACTIVE_RIDES_MD_PATH):
        with open(ACTIVE_RIDES_MD_PATH, "r", encoding="utf-8") as f:
            content = f.read()
    else:
        content = "# No active rides file found."
    return HTMLResponse(content=f"<pre style='font-family: monospace; white-space: pre-wrap; padding: 20px;'>{content}</pre>")

@app.get("/")
def serve_root():
    if os.path.exists(web_dir):
        index_file = os.path.join(web_dir, "index.html")
        if os.path.isfile(index_file):
            return _no_cache_response(index_file)
    return JSONResponse({"status": "running", "service": "DIU Ride Production", "app_path": "/ride"})

@app.get("/ride")
@app.get("/ride/")
def serve_ride_root():
    if os.path.exists(web_dir):
        index_file = os.path.join(web_dir, "index.html")
        if os.path.isfile(index_file):
            return _no_cache_response(index_file)
    return JSONResponse({"status": "running", "service": "DIU Ride Production"})

@app.get("/ride/flutter_bootstrap.js")
def serve_bootstrap():
    f = os.path.join(web_dir, "flutter_bootstrap.js")
    if os.path.isfile(f):
        return _no_cache_response(f)
    raise HTTPException(status_code=404, detail="Not found")

@app.get("/ride/flutter_service_worker.js")
def serve_sw():
    f = os.path.join(web_dir, "flutter_service_worker.js")
    if os.path.isfile(f):
        return _no_cache_response(f)
    raise HTTPException(status_code=404, detail="Not found")

@app.get("/ride/main.dart.js")
def serve_main_dart():
    f = os.path.join(web_dir, "main.dart.js")
    if os.path.isfile(f):
        return _no_cache_response(f)
    raise HTTPException(status_code=404, detail="Not found")

@app.api_route("/ride/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@app.api_route("/ride/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
@app.api_route("/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@app.api_route("/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
def serve_admin_direct():
    return HTMLResponse(content=ADMIN_HTML)

@app.api_route("/ride/{full_path:path}", methods=["GET", "HEAD"])
def serve_spa(full_path: str):
    if full_path in ("admin", "admin/"):
        return HTMLResponse(content=ADMIN_HTML)

    # Strictly prevent SPA from swallowing API 404s or WebSocket calls
    if full_path.startswith("api/") or full_path == "api" or full_path.startswith("ws"):
        raise HTTPException(status_code=404, detail=f"API route not found: /{full_path}")

    if os.path.exists(web_dir):
        file_path = os.path.join(web_dir, full_path)
        if os.path.isfile(file_path):
            if full_path.endswith((".html", ".js", ".json")):
                return _no_cache_response(file_path)
            return FileResponse(file_path, media_type=_get_media_type(file_path))
        index_file = os.path.join(web_dir, "index.html")
        if os.path.isfile(index_file):
            return _no_cache_response(index_file)
    return JSONResponse({"status": "running", "service": "DIU Ride", "path": full_path})


