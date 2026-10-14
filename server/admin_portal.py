import os
import csv
import io
import json
import sqlite3
import hashlib
from datetime import datetime
from typing import Dict, Any, Optional, List
from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from ai_service import (
    init_ai_settings_table,
    get_all_ai_settings,
    save_ai_settings,
    process_ai_chat_request,
    DEFAULT_SYSTEM_PROMPT,
    DEFAULT_GROQ_API_KEY,
    DEFAULT_MODEL_NAME,
)

admin_router = APIRouter()

SALT = "diu_ride_salt_varsity_2026"

def hash_password(password: str) -> str:
    return hashlib.sha256((SALT + password).encode("utf-8")).hexdigest()

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return hash_password(plain_password) == hashed_password

def get_db_path():
    return os.path.join(os.path.dirname(__file__), "rides.db")

def get_admin_db():
    conn = sqlite3.connect(get_db_path(), timeout=20.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def init_admin_tables():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS admins (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT DEFAULT 'superadmin',
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        last_login TEXT
    );
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS notices (
        id TEXT PRIMARY KEY,
        admin_id TEXT NOT NULL,
        admin_email TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        target_audience TEXT NOT NULL,
        priority TEXT DEFAULT 'normal',
        created_at TEXT NOT NULL
    );
    """)

    # Pre-seed main admin: 252-15-234@diu.edu.bd
    main_admin_email = "252-15-234@diu.edu.bd"
    cursor.execute("SELECT id FROM admins WHERE email = ?", (main_admin_email,))
    row = cursor.fetchone()
    if not row:
        admin_id = "adm_main_252"
        now = datetime.utcnow().isoformat()
        # Default pass: Admin@diu2026 (changeable in admin portal)
        pwd_hash = hash_password("Admin@diu2026")
        cursor.execute("""
        INSERT INTO admins (id, email, name, password_hash, role, is_active, created_at)
        VALUES (?, ?, ?, ?, ?, 1, ?)
        """, (admin_id, main_admin_email, "Varsity Authority (Main Admin)", pwd_hash, "superadmin", now))
        conn.commit()
        print(f"[ADMIN INIT] Successfully initialized main admin: {main_admin_email}")

    # Initialize AI settings table
    init_ai_settings_table(conn)

    conn.close()

# Call initialization on module load
try:
    init_admin_tables()
except Exception as e:
    print(f"[ADMIN INIT ERROR]: {e}")

# =====================================================================
# REST Endpoints: Admin Authentication & Management
# =====================================================================

@admin_router.post("/ride/api/admin/login")
@admin_router.post("/api/admin/login")
async def admin_login(payload: Dict[str, Any]):
    email = (payload.get("email") or "").strip().lower()
    password = payload.get("password") or ""
    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM admins WHERE LOWER(email) = ? AND is_active = 1", (email,))
    admin = cursor.fetchone()

    if not admin or not verify_password(password, admin["password_hash"]):
        conn.close()
        raise HTTPException(status_code=401, detail="Invalid admin credentials")

    now = datetime.utcnow().isoformat()
    cursor.execute("UPDATE admins SET last_login = ? WHERE id = ?", (now, admin["id"]))
    conn.commit()
    conn.close()

    return {
        "status": "success",
        "admin": {
            "id": admin["id"],
            "email": admin["email"],
            "name": admin["name"],
            "role": admin["role"],
            "lastLogin": now
        },
        "token": f"adm_tok_{admin['id']}_{int(datetime.utcnow().timestamp())}"
    }

@admin_router.post("/ride/api/admin/change-password")
@admin_router.post("/api/admin/change-password")
async def admin_change_password(payload: Dict[str, Any]):
    email = (payload.get("email") or "").strip().lower()
    old_password = payload.get("oldPassword") or ""
    new_password = payload.get("newPassword") or ""

    if not email or not new_password:
        raise HTTPException(status_code=400, detail="Email and new password are required")

    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters")

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM admins WHERE LOWER(email) = ? AND is_active = 1", (email,))
    admin = cursor.fetchone()

    if not admin:
        conn.close()
        raise HTTPException(status_code=404, detail="Admin account not found")

    # If old password provided, verify it (unless bypassed by superadmin)
    if old_password and not verify_password(old_password, admin["password_hash"]):
        conn.close()
        raise HTTPException(status_code=401, detail="Current password does not match")

    new_hash = hash_password(new_password)
    cursor.execute("UPDATE admins SET password_hash = ? WHERE id = ?", (new_hash, admin["id"]))
    conn.commit()
    conn.close()

    return {"status": "success", "message": f"Password updated successfully for {email}"}

@admin_router.post("/ride/api/admin/create-admin")
@admin_router.post("/api/admin/create-admin")
async def admin_create_new(payload: Dict[str, Any]):
    email = (payload.get("email") or "").strip().lower()
    name = (payload.get("name") or "").strip()
    password = payload.get("password") or ""
    role = payload.get("role") or "admin"

    if not email or not name or not password:
        raise HTTPException(status_code=400, detail="Email, name, and password are required")

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT id FROM admins WHERE LOWER(email) = ?", (email,))
    if cursor.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="An admin with this email already exists")

    admin_id = f"adm_{int(datetime.utcnow().timestamp())}"
    now = datetime.utcnow().isoformat()
    pwd_hash = hash_password(password)

    cursor.execute("""
    INSERT INTO admins (id, email, name, password_hash, role, is_active, created_at)
    VALUES (?, ?, ?, ?, ?, 1, ?)
    """, (admin_id, email, name, pwd_hash, role, now))
    conn.commit()
    conn.close()

    return {
        "status": "success",
        "message": f"New administrator {name} ({email}) created successfully",
        "admin": {"id": admin_id, "email": email, "name": name, "role": role, "createdAt": now}
    }

@admin_router.get("/ride/api/admin/admins")
@admin_router.get("/api/admin/admins")
async def admin_list():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT id, email, name, role, is_active, created_at, last_login FROM admins ORDER BY created_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "email": r["email"],
        "name": r["name"],
        "role": r["role"],
        "isActive": bool(r["is_active"]),
        "createdAt": r["created_at"],
        "lastLogin": r["last_login"] or "Never"
    } for r in rows]

# =====================================================================
# REST Endpoints: Statistics & Database Records Explorer
# =====================================================================

@admin_router.get("/ride/api/admin/stats")
@admin_router.get("/api/admin/stats")
async def admin_stats():
    conn = get_admin_db()
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM users")
    total_users = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM users WHERE is_driver_registered = 1")
    total_drivers = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM rides")
    total_rides = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM rides WHERE status = 'active'")
    active_rides = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM bookings")
    total_bookings = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM completed_rides")
    completed_rides = cursor.fetchone()[0]

    cursor.execute("SELECT COALESCE(SUM(fare), 0.0) FROM completed_rides")
    total_fare_sum = float(cursor.fetchone()[0] or 0.0)

    cursor.execute("SELECT count(*) FROM sos_alerts")
    sos_alerts = cursor.fetchone()[0]

    cursor.execute("SELECT count(*) FROM notices")
    total_notices = cursor.fetchone()[0]

    conn.close()

    return {
        "totalUsers": total_users,
        "totalDrivers": total_drivers,
        "totalPassengers": max(0, total_users - total_drivers),
        "totalRides": total_rides,
        "activeRides": active_rides,
        "totalBookings": total_bookings,
        "completedRides": completed_rides,
        "totalFareSum": round(total_fare_sum, 2),
        "sosAlerts": sos_alerts,
        "totalNotices": total_notices,
        "serverTimestamp": datetime.utcnow().isoformat(),
    }

@admin_router.get("/ride/api/admin/users")
@admin_router.get("/api/admin/users")
async def admin_get_users(role: Optional[str] = None, search: Optional[str] = None):
    conn = get_admin_db()
    cursor = conn.cursor()

    query = "SELECT * FROM users WHERE 1=1"
    params = []

    if role == "driver":
        query += " AND is_driver_registered = 1"
    elif role == "passenger":
        query += " AND is_driver_registered = 0"

    if search:
        s = f"%{search.strip()}%"
        query += " AND (name LIKE ? OR email LIKE ? OR student_id LIKE ? OR phone LIKE ? OR department LIKE ?)"
        params.extend([s, s, s, s, s])

    query += " ORDER BY created_at DESC"
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    users = []
    for r in rows:
        users.append({
            "id": r["id"],
            "studentId": r["student_id"],
            "name": r["name"],
            "email": r["email"],
            "phone": r["phone"] or "",
            "department": r["department"] or "CSE",
            "batch": r["batch"] or "",
            "rating": float(r["rating"] or 4.90),
            "isDriverRegistered": bool(r["is_driver_registered"]),
            "totalRidesAsDriver": int(r["total_rides_as_driver"] or 0),
            "totalRidesAsPassenger": int(r["total_rides_as_passenger"] or 0),
            "vehicleInfo": r["vehicle_info"] or "",
            "isVerified": bool(r["is_verified"]),
            "createdAt": r["created_at"],
        })
    return users

@admin_router.get("/ride/api/admin/rides")
@admin_router.get("/api/admin/rides")
async def admin_get_rides(status: Optional[str] = None, search: Optional[str] = None):
    conn = get_admin_db()
    cursor = conn.cursor()

    query = "SELECT * FROM rides WHERE 1=1"
    params = []

    if status and status != "all":
        query += " AND status = ?"
        params.append(status)

    if search:
        s = f"%{search.strip()}%"
        query += " AND (driver_name LIKE ? OR origin_name LIKE ? OR destination_name LIKE ? OR vehicle_model LIKE ?)"
        params.extend([s, s, s, s])

    query += " ORDER BY created_at DESC"
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    rides = []
    for r in rows:
        rides.append({
            "id": r["id"],
            "driverId": r["driver_id"],
            "driverName": r["driver_name"],
            "driverPhone": r["driver_phone"] or "",
            "driverDept": r["driver_dept"] or "DIU Student",
            "originName": r["origin_name"],
            "destinationName": r["destination_name"],
            "waypointName": r["waypoint_name"] or "",
            "departureTime": r["departure_time"],
            "farePerSeat": float(r["fare_per_seat"]),
            "totalSeats": int(r["total_seats"]),
            "availableSeats": int(r["available_seats"]),
            "status": r["status"],
            "vehicleModel": r["vehicle_model"],
            "vehiclePlate": r["vehicle_plate"] or "",
            "startTime": r["start_time"] if "start_time" in r.keys() else None,
            "endTime": r["end_time"] if "end_time" in r.keys() else None,
            "startMapsLink": r["start_maps_link"] if "start_maps_link" in r.keys() else None,
            "endMapsLink": r["end_maps_link"] if "end_maps_link" in r.keys() else None,
            "createdAt": r["created_at"],
        })
    return rides

@admin_router.get("/ride/api/admin/bookings")
@admin_router.get("/api/admin/bookings")
async def admin_get_bookings():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM bookings ORDER BY requested_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "rideId": r["ride_id"],
        "passengerId": r["passenger_id"],
        "passengerName": r["passenger_name"],
        "passengerPhone": r["passenger_phone"] or "",
        "passengerDept": r["passenger_dept"] or "DIU Student",
        "pickupPoint": r["pickup_point"],
        "dropoffPoint": r["dropoff_point"],
        "seatsBooked": int(r["seats_booked"]),
        "totalFare": float(r["total_fare"]),
        "status": r["status"],
        "requestedAt": r["requested_at"],
    } for r in rows]

@admin_router.get("/ride/api/admin/completed-rides")
@admin_router.get("/api/admin/completed-rides")
async def admin_get_completed():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM completed_rides ORDER BY completed_time DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "rideId": r["ride_id"],
        "driverId": r["driver_id"],
        "driverName": r["driver_name"],
        "passengerId": r["passenger_id"] or "",
        "passengerName": r["passenger_name"] or "",
        "originName": r["origin_name"],
        "destinationName": r["destination_name"],
        "startTime": r["start_time"] or "",
        "completedTime": r["completed_time"],
        "fare": float(r["fare"]),
        "startMapsLink": r["start_maps_link"] or "",
        "endMapsLink": r["end_maps_link"] or "",
        "rating": float(r["rating"] or 5.0),
        "feedback": r["feedback"] or "",
        "createdAt": r["created_at"],
    } for r in rows]

@admin_router.get("/ride/api/admin/sos-alerts")
@admin_router.get("/api/admin/sos-alerts")
async def admin_get_sos():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM sos_alerts ORDER BY created_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "studentId": r["student_id"],
        "studentName": r["student_name"],
        "studentPhone": r["student_phone"] or "",
        "locationName": r["location_name"] or "DIU Campus",
        "latitude": r["latitude"],
        "longitude": r["longitude"],
        "status": r["status"],
        "createdAt": r["created_at"]
    } for r in rows]

# =====================================================================
# REST Endpoints: Varsity Notices & Broadcast System
# =====================================================================

# Global reference to WebSocket connection manager, set by main.py
ws_manager_ref = None

def set_ws_manager(manager):
    global ws_manager_ref
    ws_manager_ref = manager

@admin_router.post("/ride/api/admin/notices")
@admin_router.post("/api/admin/notices")
async def admin_post_notice(payload: Dict[str, Any]):
    title = (payload.get("title") or "").strip()
    content = (payload.get("content") or "").strip()
    target_audience = (payload.get("targetAudience") or "all").lower() # "all", "riders", "passengers"
    priority = (payload.get("priority") or "normal").lower() # "normal", "urgent", "emergency"
    admin_email = payload.get("adminEmail") or "252-15-234@diu.edu.bd"

    if not title or not content:
        raise HTTPException(status_code=400, detail="Notice title and content are required")

    notice_id = f"notc_{int(datetime.utcnow().timestamp()*1000)}"
    now = datetime.utcnow().isoformat()

    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO notices (id, admin_id, admin_email, title, content, target_audience, priority, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (notice_id, "adm_main", admin_email, title, content, target_audience, priority, now))
    conn.commit()
    conn.close()

    notice_data = {
        "id": notice_id,
        "title": title,
        "body": content,
        "content": content,
        "message": content,
        "audience": target_audience,
        "targetAudience": target_audience,
        "priority": priority,
        "sender": "DIU Varsity Authority",
        "senderEmail": admin_email,
        "createdAt": now,
        "timestamp": now,
        "type": "varsity_notice"
    }

    # Broadcast to all active WebSocket clients (mobile app & web)
    if ws_manager_ref:
        try:
            await ws_manager_ref.broadcast("university_notice", notice_data)
            await ws_manager_ref.broadcast("announcement", notice_data)
            print(f"[VARSITY NOTICE BROADCAST] Sent to active WebSocket clients: {title}")
        except Exception as e:
            print(f"[NOTICE BROADCAST ERROR]: {e}")

    return {
        "status": "success",
        "message": f"Notice '{title}' broadcasted successfully to {target_audience.title()}!",
        "notice": notice_data
    }

@admin_router.get("/ride/api/admin/notices")
@admin_router.get("/api/admin/notices")
async def admin_get_notices():
    conn = get_admin_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM notices ORDER BY created_at DESC")
    rows = cursor.fetchall()
    conn.close()
    return [{
        "id": r["id"],
        "adminEmail": r["admin_email"],
        "title": r["title"],
        "content": r["content"],
        "targetAudience": r["target_audience"],
        "priority": r["priority"],
        "createdAt": r["created_at"]
    } for r in rows]

# =====================================================================
# REST Endpoints: AI Assistant Settings & Realtime Chat Proxy
# =====================================================================

@admin_router.get("/ride/api/admin/ai-settings")
@admin_router.get("/api/admin/ai-settings")
async def admin_get_ai_settings():
    conn = get_admin_db()
    try:
        settings = get_all_ai_settings(conn)
        return {"status": "success", "settings": settings}
    finally:
        conn.close()

@admin_router.post("/ride/api/admin/ai-settings")
@admin_router.post("/api/admin/ai-settings")
async def admin_update_ai_settings(payload: Dict[str, Any]):
    conn = get_admin_db()
    try:
        updated = save_ai_settings(conn, payload)
        return {
            "status": "success",
            "message": "AI Assistant settings updated successfully in database!",
            "settings": updated
        }
    finally:
        conn.close()

@admin_router.post("/ride/api/admin/ai-reset-prompt")
@admin_router.post("/api/admin/ai-reset-prompt")
async def admin_reset_ai_prompt():
    conn = get_admin_db()
    try:
        updated = save_ai_settings(conn, {
            "system_prompt": DEFAULT_SYSTEM_PROMPT,
            "groq_api_key": DEFAULT_GROQ_API_KEY,
            "model_name": DEFAULT_MODEL_NAME,
        })
        return {
            "status": "success",
            "message": "System prompt reset to default cordial DIU Ride companion prompt",
            "settings": updated
        }
    finally:
        conn.close()

@admin_router.post("/ride/api/ai/chat")
@admin_router.post("/api/ai/chat")
async def public_ai_chat_endpoint(payload: Dict[str, Any]):
    conn = get_admin_db()
    try:
        res = process_ai_chat_request(conn, payload)
        return res
    finally:
        conn.close()

# =====================================================================
# REST Endpoints: CSV & PDF Data Export
# =====================================================================

@admin_router.get("/ride/api/admin/export/csv")
@admin_router.get("/api/admin/export/csv")
async def export_csv(type: str = "rides"):
    conn = get_admin_db()
    cursor = conn.cursor()
    output = io.StringIO()
    filename = f"diu_ride_{type}_{int(datetime.utcnow().timestamp())}.csv"

    if type == "users" or type == "riders" or type == "passengers":
        if type == "riders":
            cursor.execute("SELECT * FROM users WHERE is_driver_registered = 1 ORDER BY created_at DESC")
        elif type == "passengers":
            cursor.execute("SELECT * FROM users WHERE is_driver_registered = 0 ORDER BY created_at DESC")
        else:
            cursor.execute("SELECT * FROM users ORDER BY created_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["student_id", "name", "email", "phone", "department", "batch", "role", "rating", "total_rides_as_driver", "total_rides_as_passenger", "vehicle_info", "is_verified", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "student_id": r["student_id"],
                "name": r["name"],
                "email": r["email"],
                "phone": r["phone"] or "",
                "department": r["department"] or "CSE",
                "batch": r["batch"] or "",
                "role": "Biker / Rider" if r["is_driver_registered"] else "Passenger",
                "rating": r["rating"],
                "total_rides_as_driver": r["total_rides_as_driver"] or 0,
                "total_rides_as_passenger": r["total_rides_as_passenger"] or 0,
                "vehicle_info": r["vehicle_info"] or "",
                "is_verified": "Yes" if r["is_verified"] else "No",
                "created_at": r["created_at"]
            })

    elif type == "completed":
        cursor.execute("SELECT * FROM completed_rides ORDER BY completed_time DESC")
        rows = cursor.fetchall()
        fieldnames = ["trip_id", "driver_name", "driver_id", "passenger_name", "passenger_id", "origin", "destination", "start_time", "completed_time", "fare", "start_maps_link", "end_maps_link", "rating", "feedback"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "trip_id": r["id"],
                "driver_name": r["driver_name"],
                "driver_id": r["driver_id"],
                "passenger_name": r["passenger_name"] or "",
                "passenger_id": r["passenger_id"] or "",
                "origin": r["origin_name"],
                "destination": r["destination_name"],
                "start_time": r["start_time"] or "",
                "completed_time": r["completed_time"],
                "fare": r["fare"],
                "start_maps_link": r["start_maps_link"] or "",
                "end_maps_link": r["end_maps_link"] or "",
                "rating": r["rating"],
                "feedback": r["feedback"] or "",
            })

    elif type == "bookings":
        cursor.execute("SELECT * FROM bookings ORDER BY requested_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["booking_id", "ride_id", "passenger_name", "passenger_id", "passenger_phone", "pickup_point", "dropoff_point", "seats_booked", "total_fare", "status", "requested_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "booking_id": r["id"],
                "ride_id": r["ride_id"],
                "passenger_name": r["passenger_name"],
                "passenger_id": r["passenger_id"],
                "passenger_phone": r["passenger_phone"] or "",
                "pickup_point": r["pickup_point"],
                "dropoff_point": r["dropoff_point"],
                "seats_booked": r["seats_booked"],
                "total_fare": r["total_fare"],
                "status": r["status"],
                "requested_at": r["requested_at"]
            })

    else: # type == 'rides' or default
        cursor.execute("SELECT * FROM rides ORDER BY created_at DESC")
        rows = cursor.fetchall()
        fieldnames = ["ride_id", "driver_name", "driver_id", "driver_phone", "origin", "destination", "waypoint", "departure_time", "fare_per_seat", "available_seats", "status", "bike_model", "bike_plate", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow({
                "ride_id": r["id"],
                "driver_name": r["driver_name"],
                "driver_id": r["driver_id"],
                "driver_phone": r["driver_phone"] or "",
                "origin": r["origin_name"],
                "destination": r["destination_name"],
                "waypoint": r["waypoint_name"] or "",
                "departure_time": r["departure_time"],
                "fare_per_seat": r["fare_per_seat"],
                "available_seats": r["available_seats"],
                "status": r["status"],
                "bike_model": r["vehicle_model"],
                "bike_plate": r["vehicle_plate"] or "",
                "created_at": r["created_at"]
            })

    conn.close()
    output.seek(0)
    return StreamingResponse(
        io.BytesIO(output.getvalue().encode("utf-8")),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )

@admin_router.get("/ride/api/admin/export/pdf")
@admin_router.get("/api/admin/export/pdf")
async def export_printable_pdf(type: str = "all"):
    """
    Generates an official, print-ready DIU Varsity Authority Commute Audit Report
    which directly opens the browser's high-resolution print/PDF engine with university letterhead.
    """
    conn = get_admin_db()
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM users")
    tot_users = cursor.fetchone()[0]
    cursor.execute("SELECT count(*) FROM users WHERE is_driver_registered = 1")
    tot_drivers = cursor.fetchone()[0]
    cursor.execute("SELECT count(*) FROM rides")
    tot_rides = cursor.fetchone()[0]
    cursor.execute("SELECT count(*) FROM completed_rides")
    tot_comp = cursor.fetchone()[0]
    cursor.execute("SELECT COALESCE(SUM(fare), 0) FROM completed_rides")
    tot_fare = cursor.fetchone()[0]

    cursor.execute("SELECT * FROM completed_rides ORDER BY completed_time DESC LIMIT 50")
    comp_rows = cursor.fetchall()

    cursor.execute("SELECT * FROM users WHERE is_driver_registered = 1 ORDER BY created_at DESC LIMIT 50")
    driver_rows = cursor.fetchall()

    conn.close()

    now_str = datetime.now().strftime("%B %d, %Y - %I:%M %p")

    comp_table_rows = ""
    for r in comp_rows:
        comp_table_rows += f"""
        <tr>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['id']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-weight: bold; font-size: 11px;">{r['driver_name']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['passenger_name'] or 'Commuter'}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['origin_name']} ➔ {r['destination_name']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{r['completed_time'][:16].replace('T', ' ')}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-weight: bold; font-size: 11px; text-align: right;">৳{r['fare']:.0f}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px; text-align: center;">⭐ {r['rating']}</td>
        </tr>
        """

    drivers_table_rows = ""
    for d in driver_rows:
        drivers_table_rows += f"""
        <tr>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['student_id']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-weight: bold; font-size: 11px;">{d['name']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['department']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['phone']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px;">{d['vehicle_info'] or 'Motorbike'}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px; text-align: center;">{d['total_rides_as_driver']}</td>
            <td style="padding: 8px; border-bottom: 1px solid #E5E7EB; font-size: 11px; text-align: center;">⭐ {d['rating']}</td>
        </tr>
        """

    html = f"""<!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>DIU Ride Official Audit Report - Daffodil International University</title>
        <style>
            @page {{ size: A4 portrait; margin: 15mm; }}
            body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; color: #1F2937; margin: 0; padding: 20px; }}
            .header {{ display: flex; align-items: center; justify-content: space-between; border-bottom: 3px solid #1B5E20; padding-bottom: 15px; margin-bottom: 20px; }}
            .logo-area h1 {{ margin: 0; font-size: 22px; color: #1B5E20; font-weight: 800; }}
            .logo-area p {{ margin: 3px 0 0; font-size: 12px; color: #6B7280; }}
            .meta {{ text-align: right; font-size: 11px; color: #4B5563; }}
            .badge {{ display: inline-block; background: #E8F5E9; color: #166534; padding: 4px 10px; border-radius: 12px; font-weight: bold; font-size: 11px; margin-bottom: 4px; }}
            .kpi-grid {{ display: grid; grid-template-columns: repeat(5, 1fr); gap: 10px; margin-bottom: 25px; }}
            .kpi-card {{ background: #F9FAFB; border: 1px solid #E5E7EB; border-radius: 8px; padding: 10px; text-align: center; }}
            .kpi-val {{ font-size: 18px; font-weight: 800; color: #111827; }}
            .kpi-lbl {{ font-size: 10px; color: #6B7280; text-transform: uppercase; margin-top: 2px; }}
            h2 {{ font-size: 14px; color: #1B5E20; border-left: 4px solid #E65100; padding-left: 8px; margin: 24px 0 10px 0; }}
            table {{ width: 100%; border-collapse: collapse; margin-bottom: 20px; }}
            th {{ background: #F3F4F6; color: #374151; font-size: 11px; font-weight: 700; text-align: left; padding: 8px; border-bottom: 2px solid #D1D5DB; }}
            .footer-sign {{ margin-top: 50px; display: flex; justify-content: space-between; font-size: 12px; page-break-inside: avoid; }}
            .sign-box {{ width: 220px; text-align: center; border-top: 1px dashed #9CA3AF; padding-top: 8px; }}
            @media print {{
                .no-print {{ display: none !important; }}
                body {{ padding: 0; }}
            }}
        </style>
    </head>
    <body>
        <div class="no-print" style="margin-bottom: 20px; background: #1B5E20; padding: 12px 20px; border-radius: 8px; color: white; display: flex; justify-content: space-between; align-items: center;">
            <div style="font-weight: bold;">🖨️ DIU Transport Authority Official Printable Report</div>
            <div>
                <button onclick="window.print()" style="background: #E65100; color: white; border: none; padding: 8px 16px; border-radius: 6px; font-weight: bold; cursor: pointer;">Save as PDF / Print</button>
                <button onclick="window.close()" style="background: rgba(255,255,255,0.2); color: white; border: none; padding: 8px 14px; border-radius: 6px; margin-left: 8px; cursor: pointer;">Close</button>
            </div>
        </div>

        <div class="header">
            <div class="logo-area">
                <div class="badge">DAFFODIL INTERNATIONAL UNIVERSITY</div>
                <h1>DIU RIDE • CAMPUS COMMUTE AUDIT REPORT</h1>
                <p>Office of the Directorate of Student Affairs & Campus Transport Cell • Daffodil Smart City, Ashulia</p>
            </div>
            <div class="meta">
                <div><strong>Report Date:</strong> {now_str}</div>
                <div><strong>Authority Admin:</strong> 252-15-234@diu.edu.bd</div>
                <div><strong>Classification:</strong> Official University Record</div>
            </div>
        </div>

        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-val">{tot_users}</div>
                <div class="kpi-lbl">Total Students</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">{tot_drivers}</div>
                <div class="kpi-lbl">Verified Bikers</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">{tot_rides}</div>
                <div class="kpi-lbl">Total Rides Offered</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">{tot_comp}</div>
                <div class="kpi-lbl">Completed Trips</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-val">৳{tot_fare:.0f}</div>
                <div class="kpi-lbl">Fuel Split Fare (BDT)</div>
            </div>
        </div>

        <h2>Section 1: Completed Rides & Route Audit Log (Recent Sample)</h2>
        <table>
            <thead>
                <tr>
                    <th>Trip ID</th>
                    <th>Driver / Biker</th>
                    <th>Passenger</th>
                    <th>Corridor (Route)</th>
                    <th>Completed Time</th>
                    <th style="text-align: right;">Fare</th>
                    <th style="text-align: center;">Rating</th>
                </tr>
            </thead>
            <tbody>
                {comp_table_rows}
            </tbody>
        </table>

        <h2>Section 2: Registered Student Motorbike Providers</h2>
        <table>
            <thead>
                <tr>
                    <th>Student ID</th>
                    <th>Rider Name</th>
                    <th>Department</th>
                    <th>Phone</th>
                    <th>Motorbike Model & Plate</th>
                    <th style="text-align: center;">Rides</th>
                    <th style="text-align: center;">Rating</th>
                </tr>
            </thead>
            <tbody>
                {drivers_table_rows}
            </tbody>
        </table>

        <div class="footer-sign">
            <div class="sign-box">
                Prepared by<br>
                <strong>Transport Operations Desk</strong>
            </div>
            <div class="sign-box">
                Verified by<br>
                <strong>Main Authority Admin (252-15-234)</strong>
            </div>
            <div class="sign-box">
                Approved by<br>
                <strong>Proctor & Student Affairs Cell</strong>
            </div>
        </div>

        <script>
            // Automatically prompt print dialog on load
            window.addEventListener('load', () => {{
                setTimeout(() => {{ window.print(); }}, 500);
            }});
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html)

# =====================================================================
# REST Endpoints: Full Single-Page Admin Portal Web Application
# =====================================================================

ADMIN_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DIU Ride - Varsity Authority Admin Portal</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #1B5E20;
            --primary-dark: #0D3E12;
            --primary-light: #2E7D32;
            --accent: #E65100;
            --accent-light: #F57C00;
            --surface: #0F172A;
            --bg: #F8FAFC;
            --card-bg: #FFFFFF;
            --border: #E2E8F0;
            --text-main: #0F172A;
            --text-muted: #64748B;
            --danger: #EF4444;
            --success: #10B981;
            --warning: #F59E0B;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', sans-serif; }
        body { background-color: var(--bg); color: var(--text-main); min-height: 100vh; display: flex; flex-direction: column; }

        /* Top Navbar */
        .navbar {
            background: linear-gradient(135deg, var(--primary-dark) 0%, var(--primary) 60%, #166534 100%);
            color: #FFFFFF;
            padding: 14px 28px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            box-shadow: 0 4px 20px rgba(0,0,0,0.12);
            position: sticky;
            top: 0;
            z-index: 50;
        }

        .brand-box { display: flex; align-items: center; gap: 12px; }
        .brand-icon {
            width: 42px; height: 42px; background: rgba(255,255,255,0.18);
            border-radius: 12px; display: flex; align-items: center; justify-content: center;
            font-size: 22px; border: 1px solid rgba(255,255,255,0.25);
        }
        .brand-text h1 { font-size: 19px; font-weight: 800; letter-spacing: -0.3px; }
        .brand-text p { font-size: 11.5px; opacity: 0.85; font-weight: 500; }

        .nav-actions { display: flex; align-items: center; gap: 10px; }
        .btn {
            padding: 8px 16px; border-radius: 10px; font-weight: 700; font-size: 12.5px;
            cursor: pointer; border: none; transition: all 0.2s; display: inline-flex; align-items: center; gap: 6px;
        }
        .btn-accent { background: var(--accent); color: white; }
        .btn-accent:hover { background: var(--accent-light); transform: translateY(-1px); }
        .btn-outline { background: rgba(255,255,255,0.14); color: white; border: 1px solid rgba(255,255,255,0.3); }
        .btn-outline:hover { background: rgba(255,255,255,0.25); }
        .btn-secondary { background: #E2E8F0; color: #1E293B; }
        .btn-secondary:hover { background: #CBD5E1; }
        .btn-danger { background: #FEE2E2; color: #991B1B; }

        /* Container Layout */
        .layout { display: flex; flex: 1; max-width: 1600px; width: 100%; margin: 0 auto; padding: 24px; gap: 24px; }
        .sidebar { width: 260px; display: flex; flex-direction: column; gap: 6px; }
        .nav-tab {
            padding: 12px 16px; border-radius: 12px; font-weight: 700; font-size: 13.5px;
            color: var(--text-muted); cursor: pointer; transition: all 0.15s; display: flex; align-items: center; gap: 10px;
        }
        .nav-tab:hover { background: #E2E8F0; color: var(--text-main); }
        .nav-tab.active { background: var(--primary); color: white; box-shadow: 0 4px 12px rgba(27,94,32,0.25); }

        .main-content { flex: 1; display: flex; flex-direction: column; gap: 20px; overflow-x: hidden; }

        /* KPI Cards Grid */
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; }
        .stat-card {
            background: white; border: 1px solid var(--border); border-radius: 16px; padding: 18px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.03); display: flex; flex-direction: column; gap: 6px;
        }
        .stat-label { font-size: 12px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
        .stat-value { font-size: 28px; font-weight: 800; color: var(--text-main); }
        .stat-desc { font-size: 11.5px; color: #10B981; font-weight: 600; }

        /* Card Section */
        .content-card {
            background: white; border: 1px solid var(--border); border-radius: 18px;
            box-shadow: 0 4px 16px rgba(0,0,0,0.04); overflow: hidden; display: flex; flex-direction: column;
        }
        .card-header {
            padding: 16px 20px; border-bottom: 1px solid var(--border); display: flex;
            align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px;
        }
        .card-title { font-size: 16px; font-weight: 800; color: var(--text-main); display: flex; align-items: center; gap: 8px; }

        .toolbar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
        .search-input {
            padding: 8px 14px; border: 1.5px solid var(--border); border-radius: 10px; font-size: 13px;
            min-width: 240px; outline: none; transition: border-color 0.2s;
        }
        .search-input:focus { border-color: var(--primary); }
        select.filter-select {
            padding: 8px 12px; border: 1.5px solid var(--border); border-radius: 10px; font-size: 13px;
            background: white; outline: none;
        }

        /* Table Styling */
        .table-responsive { width: 100%; overflow-x: auto; max-height: 600px; }
        table.data-table { width: 100%; border-collapse: collapse; text-align: left; font-size: 13px; }
        table.data-table th {
            background: #F8FAFC; color: #475569; font-weight: 700; padding: 12px 16px;
            border-bottom: 1.5px solid var(--border); position: sticky; top: 0; z-index: 10;
        }
        table.data-table td { padding: 12px 16px; border-bottom: 1px solid #F1F5F9; color: #334155; }
        table.data-table tr:hover { background-color: #F8FAFC; }

        .pill {
            display: inline-block; padding: 3px 8px; border-radius: 8px; font-size: 11px; font-weight: 700;
        }
        .pill-green { background: #ECFDF5; color: #047857; }
        .pill-blue { background: #EFF6FF; color: #1D4ED8; }
        .pill-amber { background: #FFFBEB; color: #B45309; }
        .pill-red { background: #FEF2F2; color: #B91C1C; }

        /* Modal */
        .modal-overlay {
            position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5);
            display: none; align-items: center; justify-content: center; z-index: 100; padding: 20px;
        }
        .modal {
            background: white; border-radius: 20px; max-width: 540px; width: 100%; padding: 26px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.2); display: flex; flex-direction: column; gap: 16px;
        }
        .modal-header { display: flex; justify-content: space-between; align-items: center; }
        .form-group { display: flex; flex-direction: column; gap: 6px; }
        .form-group label { font-size: 12.5px; font-weight: 700; color: #334155; }
        .form-control {
            padding: 10px 14px; border: 1.5px solid var(--border); border-radius: 10px; font-size: 13.5px; outline: none;
        }
        .form-control:focus { border-color: var(--primary); }

        /* Login Screen */
        .login-wrap {
            position: fixed; inset: 0; background: linear-gradient(135deg, #0F3820 0%, #1B5E20 50%, #0F172A 100%);
            display: flex; align-items: center; justify-content: center; z-index: 200; padding: 20px;
        }
        .login-card {
            background: white; border-radius: 24px; padding: 36px; max-width: 440px; width: 100%;
            box-shadow: 0 25px 50px rgba(0,0,0,0.3); text-align: center; display: flex; flex-direction: column; gap: 18px;
        }

        @media (max-width: 900px) {
            .layout { flex-direction: column; padding: 12px; }
            .sidebar { width: 100%; flex-direction: row; overflow-x: auto; padding-bottom: 8px; }
            .nav-tab { white-space: nowrap; }
        }
    </style>
</head>
<body>

    <!-- AUTHENTICATION GATE SCREEN -->
    <div id="loginGate" class="login-wrap">
        <div class="login-card">
            <div style="width: 58px; height: 58px; background: #E8F5E9; color: var(--primary); border-radius: 18px; display: flex; align-items: center; justify-content: center; font-size: 28px; margin: 0 auto;">
                🛡️
            </div>
            <div>
                <h2 style="font-size: 22px; font-weight: 800; color: #0F172A;">Varsity Authority Login</h2>
                <p style="font-size: 13px; color: var(--text-muted); margin-top: 4px;">Daffodil International University • Transport Management Cell</p>
            </div>
            <div style="background: #F1F5F9; border-radius: 12px; padding: 10px 14px; font-size: 12px; color: #475569; text-align: left;">
                👤 <strong>Super Admin:</strong> <code>252-15-234@diu.edu.bd</code><br>
                🔑 <strong>Default Password:</strong> <code>Admin@diu2026</code>
            </div>
            <div class="form-group" style="text-align: left;">
                <label>Administrator Email</label>
                <input id="loginEmail" type="email" class="form-control" value="252-15-234@diu.edu.bd" placeholder="admin@diu.edu.bd">
            </div>
            <div class="form-group" style="text-align: left;">
                <label>Password</label>
                <input id="loginPass" type="password" class="form-control" value="Admin@diu2026" placeholder="Enter password">
            </div>
            <div id="loginErr" style="color: var(--danger); font-size: 12.5px; font-weight: 700; display: none;"></div>
            <button class="btn btn-accent" style="justify-content: center; padding: 12px; font-size: 14px;" onclick="doAdminLogin()">
                Access Authority Portal ➔
            </button>
        </div>
    </div>

    <!-- MAIN APP NAVBAR -->
    <header class="navbar">
        <div class="brand-box">
            <div class="brand-icon">🏍️</div>
            <div class="brand-text">
                <h1>DIU RIDE AUTHORITY PORTAL</h1>
                <p>Campus Commute Realtime Database & Administration • Daffodil Smart City</p>
            </div>
        </div>
        <div class="nav-actions">
            <a href="/download-apk" class="btn btn-outline" style="text-decoration: none; color: white;" download>📥 Download APK (v1.0.1)</a>
            <button class="btn btn-accent" onclick="openNoticeModal()">📢 Broadcast Notice</button>
            <button class="btn btn-outline" onclick="openPassModal()">🔑 Change Password</button>
            <button class="btn btn-outline" onclick="openAddAdminModal()">➕ Add Admin</button>
            <button class="btn btn-outline" onclick="doLogout()">🚪 Exit</button>
        </div>
    </header>

    <!-- CONTENT LAYOUT -->
    <div class="layout">
        <!-- SIDEBAR -->
        <nav class="sidebar">
            <div class="nav-tab active" onclick="switchTab('dashboard')">📊 Executive Dashboard</div>
            <div class="nav-tab" onclick="switchTab('users')">👥 Students & Commuters</div>
            <div class="nav-tab" onclick="switchTab('riders')">🏍️ Motorbike Riders</div>
            <div class="nav-tab" onclick="switchTab('passengers')">🎒 Passenger Directory</div>
            <div class="nav-tab" onclick="switchTab('rides')">🛣️ Live Rides & Routes</div>
            <div class="nav-tab" onclick="switchTab('bookings')">📑 Booking Orders</div>
            <div class="nav-tab" onclick="switchTab('completed')">🏁 Completed Trips Audit</div>
            <div class="nav-tab" onclick="switchTab('sos')">🚨 Emergency SOS Logs</div>
            <div class="nav-tab" onclick="switchTab('notices')">📢 University Notices</div>
            <div class="nav-tab" onclick="switchTab('admins')">🛡️ Authority Admins</div>
            <div class="nav-tab" onclick="switchTab('ai_assistant')">🤖 DIU AI Agent Settings</div>
        </nav>

        <!-- MAIN AREA -->
        <main class="main-content">
            <!-- KPIS (Always Visible) -->
            <div class="stats-grid">
                <div class="stat-card">
                    <span class="stat-label">Total Students</span>
                    <span class="stat-value" id="kpiUsers">0</span>
                    <span class="stat-desc">Active in DIU Ride</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">Verified Bikers</span>
                    <span class="stat-value" id="kpiDrivers" style="color: var(--primary);">0</span>
                    <span class="stat-desc">Offering Campus Seats</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">Passengers</span>
                    <span class="stat-value" id="kpiPassengers">0</span>
                    <span class="stat-desc">Commuting Peers</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">Active Rides Right Now</span>
                    <span class="stat-value" id="kpiActiveRides" style="color: var(--accent);">0</span>
                    <span class="stat-desc">Live on Road / Corridor</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">Completed Trips</span>
                    <span class="stat-value" id="kpiCompleted">0</span>
                    <span class="stat-desc">Audited & Verified</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">Fuel Cost Shared</span>
                    <span class="stat-value" id="kpiFare">৳0</span>
                    <span class="stat-desc">Student Carpool Total</span>
                </div>
            </div>

            <!-- DYNAMIC TAB PANELS -->
            <div id="panelContent">
                <!-- Loaded via JS -->
            </div>
        </main>
    </div>

    <!-- BROADCAST NOTICE MODAL -->
    <div id="noticeModal" class="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3 style="font-size: 17px; font-weight: 800; color: var(--primary);">📢 Broadcast University Notice</h3>
                <button onclick="closeModal('noticeModal')" style="background: none; border: none; font-size: 18px; cursor: pointer;">✕</button>
            </div>
            <p style="font-size: 12.5px; color: var(--text-muted);">
                This notification will be transmitted in real-time to all connected student phones and mobile app terminals with alert sound.
            </p>
            <div class="form-group">
                <label>Notice Headline / Title</label>
                <input id="notcTitle" type="text" class="form-control" placeholder="e.g. Birulia Highway Alert / Exam Rush Rides">
            </div>
            <div class="form-group">
                <label>Notice Content & Instructions</label>
                <textarea id="notcContent" class="form-control" rows="4" placeholder="Enter clear, concise instructions for commuters..."></textarea>
            </div>
            <div class="form-group">
                <label>Target Audience</label>
                <select id="notcAudience" class="form-control">
                    <option value="all">Everyone (All Riders & Passengers)</option>
                    <option value="riders">Bikers Only (Motorbike Riders)</option>
                    <option value="passengers">Passengers Only</option>
                </select>
            </div>
            <div class="form-group">
                <label>Priority Severity</label>
                <select id="notcPriority" class="form-control">
                    <option value="normal">Normal Bulletin</option>
                    <option value="urgent">Urgent Commute Alert</option>
                    <option value="emergency">Emergency Security Bulletin</option>
                </select>
            </div>
            <button class="btn btn-accent" style="justify-content: center; padding: 12px;" onclick="submitNotice()">
                🚀 Broadcast Notice to Phones Now
            </button>
        </div>
    </div>

    <!-- CHANGE PASSWORD MODAL -->
    <div id="passModal" class="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3 style="font-size: 17px; font-weight: 800; color: var(--primary);">🔑 Update Admin Password</h3>
                <button onclick="closeModal('passModal')" style="background: none; border: none; font-size: 18px; cursor: pointer;">✕</button>
            </div>
            <div class="form-group">
                <label>Admin Email</label>
                <input id="chgEmail" type="email" class="form-control" value="252-15-234@diu.edu.bd">
            </div>
            <div class="form-group">
                <label>Current Password (Optional)</label>
                <input id="chgOldPass" type="password" class="form-control" placeholder="Current password">
            </div>
            <div class="form-group">
                <label>New Password (Min 6 characters)</label>
                <input id="chgNewPass" type="password" class="form-control" placeholder="New secure password">
            </div>
            <button class="btn btn-accent" style="justify-content: center; padding: 12px;" onclick="submitPasswordChange()">
                Save New Password
            </button>
        </div>
    </div>

    <!-- ADD ADMIN MODAL -->
    <div id="addAdminModal" class="modal-overlay">
        <div class="modal">
            <div class="modal-header">
                <h3 style="font-size: 17px; font-weight: 800; color: var(--primary);">➕ Add New Varsity Authority Admin</h3>
                <button onclick="closeModal('addAdminModal')" style="background: none; border: none; font-size: 18px; cursor: pointer;">✕</button>
            </div>
            <div class="form-group">
                <label>Administrator Name</label>
                <input id="newAdmName" type="text" class="form-control" placeholder="e.g. Dr. Transport Coordinator">
            </div>
            <div class="form-group">
                <label>University Email</label>
                <input id="newAdmEmail" type="email" class="form-control" placeholder="e.g. proctor.office@diu.edu.bd">
            </div>
            <div class="form-group">
                <label>Password</label>
                <input id="newAdmPass" type="password" class="form-control" placeholder="Set temporary password">
            </div>
            <div class="form-group">
                <label>Role Privilege</label>
                <select id="newAdmRole" class="form-control">
                    <option value="admin">Standard Authority Admin</option>
                    <option value="superadmin">Super Admin (Full Access)</option>
                    <option value="proctor">Proctor Office Inspector</option>
                </select>
            </div>
            <button class="btn btn-accent" style="justify-content: center; padding: 12px;" onclick="submitAddAdmin()">
                Create Administrator
            </button>
        </div>
    </div>

    <script>
        let currentTab = 'dashboard';
        let loggedInAdmin = null;

        // Check persistent auth in localStorage
        const storedAdmin = localStorage.getItem('diu_admin_auth');
        if (storedAdmin) {
            try {
                loggedInAdmin = JSON.parse(storedAdmin);
                document.getElementById('loginGate').style.display = 'none';
                initDashboard();
            } catch(e) {
                document.getElementById('loginGate').style.display = 'flex';
            }
        } else {
            document.getElementById('loginGate').style.display = 'flex';
        }

        async function doAdminLogin() {
            const email = document.getElementById('loginEmail').value.trim();
            const password = document.getElementById('loginPass').value;
            const err = document.getElementById('loginErr');
            err.style.display = 'none';

            try {
                const res = await fetch('/ride/api/admin/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, password })
                });
                const data = await res.json();
                if (!res.ok) throw new Error(data.detail || 'Login failed');

                loggedInAdmin = data.admin;
                localStorage.setItem('diu_admin_auth', JSON.stringify(loggedInAdmin));
                document.getElementById('loginGate').style.display = 'none';
                initDashboard();
            } catch(e) {
                err.innerText = e.message;
                err.style.display = 'block';
            }
        }

        function doLogout() {
            localStorage.removeItem('diu_admin_auth');
            location.reload();
        }

        async function initDashboard() {
            await fetchStats();
            switchTab('dashboard');
        }

        async function fetchStats() {
            try {
                const res = await fetch('/ride/api/admin/stats');
                const d = await res.json();
                document.getElementById('kpiUsers').innerText = d.totalUsers;
                document.getElementById('kpiDrivers').innerText = d.totalDrivers;
                document.getElementById('kpiPassengers').innerText = d.totalPassengers;
                document.getElementById('kpiActiveRides').innerText = d.activeRides;
                document.getElementById('kpiCompleted').innerText = d.completedRides;
                document.getElementById('kpiFare').innerText = '৳' + Math.round(d.totalFareSum);
            } catch(e) {}
        }

        function switchTab(tab) {
            currentTab = tab;
            document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));
            const matchingTab = Array.from(document.querySelectorAll('.nav-tab')).find(el => el.getAttribute('onclick').includes(tab));
            if (matchingTab) matchingTab.classList.add('active');

            const container = document.getElementById('panelContent');
            container.innerHTML = '<div style="padding: 40px; text-align: center; color: var(--text-muted); font-weight: bold;">Loading realtime database records...</div>';

            if (tab === 'dashboard') renderDashboardTab(container);
            else if (tab === 'users') renderUsersTab(container, 'all');
            else if (tab === 'riders') renderUsersTab(container, 'driver');
            else if (tab === 'passengers') renderUsersTab(container, 'passenger');
            else if (tab === 'rides') renderRidesTab(container);
            else if (tab === 'bookings') renderBookingsTab(container);
            else if (tab === 'completed') renderCompletedTab(container);
            else if (tab === 'sos') renderSosTab(container);
            else if (tab === 'notices') renderNoticesTab(container);
            else if (tab === 'admins') renderAdminsTab(container);
            else if (tab === 'ai_assistant') renderAiAssistantTab(container);
        }

        // =================================================================
        // Tab Renderers
        // =================================================================

        async function renderDashboardTab(container) {
            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🛡️ University Transport Operations Overview</div>
                        <div class="toolbar">
                            <button class="btn btn-accent" onclick="window.open('/ride/api/admin/export/pdf', '_blank')">🖨️ Download Official PDF Report</button>
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=all', '_blank')">📥 Download All CSV Data</button>
                        </div>
                    </div>
                    <div style="padding: 24px; display: flex; flex-direction: column; gap: 20px;">
                        <div style="background: #F0FDF4; border: 1.5px solid #86EFAC; border-radius: 14px; padding: 18px; color: #166534; font-size: 13.5px; line-height: 1.6;">
                            <strong>🏛️ Authority Portal Active:</strong> Welcome, <strong>${loggedInAdmin?.name || 'Varsity Authority'}</strong> (${loggedInAdmin?.email || '252-15-234@diu.edu.bd'}).
                            From this portal, university transport administrators and proctorial body can audit live campus rides, monitor student driver profiles, verify GPS trails, broadcast campus safety notices, and export archival records in CSV/PDF.
                        </div>

                        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 16px;">
                            <div style="border: 1px solid var(--border); border-radius: 14px; padding: 16px; background: white;">
                                <h4 style="font-size: 14px; font-weight: 800; color: var(--primary); margin-bottom: 8px;">🏍️ Active Corridor Motorbikes</h4>
                                <p style="font-size: 12.5px; color: var(--text-muted); line-height: 1.5;">
                                    Track student riders offering campus commutes across Ashulia, Mirpur, Uttara, Dhanmondi, and ECB Chattar corridors.
                                </p>
                                <button class="btn btn-secondary" style="margin-top: 12px; width: 100%;" onclick="switchTab('rides')">View Active Rides ➔</button>
                            </div>
                            <div style="border: 1px solid var(--border); border-radius: 14px; padding: 16px; background: white;">
                                <h4 style="font-size: 14px; font-weight: 800; color: var(--accent); margin-bottom: 8px;">📢 Instant Notice Broadcaster</h4>
                                <p style="font-size: 12.5px; color: var(--text-muted); line-height: 1.5;">
                                    Transmit urgent weather advisories, schedule changes, or gate security notices directly to student mobile terminals.
                                </p>
                                <button class="btn btn-accent" style="margin-top: 12px; width: 100%;" onclick="openNoticeModal()">Broadcast Notice Now ➔</button>
                            </div>
                            <div style="border: 1px solid var(--border); border-radius: 14px; padding: 16px; background: white;">
                                <h4 style="font-size: 14px; font-weight: 800; color: #1E293B; margin-bottom: 8px;">📑 Compliance & Archival Center</h4>
                                <p style="font-size: 12.5px; color: var(--text-muted); line-height: 1.5;">
                                    Download full university records of completed trips with exact start GPS, arrival time, and route coordinates.
                                </p>
                                <button class="btn btn-secondary" style="margin-top: 12px; width: 100%;" onclick="switchTab('completed')">View Completed Trips Log ➔</button>
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }

        async function renderUsersTab(container, roleFilter) {
            const res = await fetch(`/ride/api/admin/users${roleFilter !== 'all' ? '?role=' + roleFilter : ''}`);
            const users = await res.json();

            const title = roleFilter === 'driver' ? '🏍️ Verified Motorbike Riders (Bikers)' : (roleFilter === 'passenger' ? '🎒 Registered Passengers' : '👥 All Registered Students');
            const csvType = roleFilter === 'driver' ? 'riders' : (roleFilter === 'passenger' ? 'passengers' : 'users');

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">${title} (${users.length})</div>
                        <div class="toolbar">
                            <input type="text" class="search-input" id="tblSearch" placeholder="Search by name, ID, or dept..." oninput="filterTableRows(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=${csvType}', '_blank')">📥 Export CSV</button>
                            <button class="btn btn-accent" onclick="window.open('/ride/api/admin/export/pdf', '_blank')">🖨️ Print PDF</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table" id="dataTable">
                            <thead>
                                <tr>
                                    <th>Student ID</th>
                                    <th>Full Name</th>
                                    <th>Department</th>
                                    <th>Email</th>
                                    <th>Phone</th>
                                    <th>Role</th>
                                    <th>Rating</th>
                                    <th>Rider Rides</th>
                                    <th>Passenger Rides</th>
                                    <th>Motorbike / Vehicle</th>
                                    <th>Joined</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${users.map(u => `
                                    <tr>
                                        <td style="font-weight: 700; font-family: monospace;">${u.studentId}</td>
                                        <td style="font-weight: 700;">${u.name}</td>
                                        <td><span class="pill pill-blue">${u.department}</span></td>
                                        <td>${u.email}</td>
                                        <td>${u.phone || '—'}</td>
                                        <td>${u.isDriverRegistered ? '<span class="pill pill-green">Biker / Rider</span>' : '<span class="pill pill-amber">Passenger</span>'}</td>
                                        <td>⭐ ${u.rating.toFixed(2)}</td>
                                        <td style="font-weight: bold; text-align: center;">${u.totalRidesAsDriver}</td>
                                        <td style="font-weight: bold; text-align: center;">${u.totalRidesAsPassenger}</td>
                                        <td>${u.vehicleInfo || '—'}</td>
                                        <td style="font-size: 11px; color: var(--text-muted);">${u.createdAt ? u.createdAt.slice(0, 10) : '—'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderRidesTab(container) {
            const res = await fetch('/ride/api/admin/rides');
            const rides = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🛣️ Motorbike Rides & Routes (${rides.length})</div>
                        <div class="toolbar">
                            <input type="text" class="search-input" placeholder="Search rider, corridor, origin..." oninput="filterTableRows(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=rides', '_blank')">📥 Export CSV</button>
                            <button class="btn btn-accent" onclick="window.open('/ride/api/admin/export/pdf', '_blank')">🖨️ Print PDF</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Ride ID</th>
                                    <th>Rider / Driver</th>
                                    <th>Department</th>
                                    <th>Origin ➔ Destination</th>
                                    <th>Departure</th>
                                    <th>Fare / Seat</th>
                                    <th>Available</th>
                                    <th>Status</th>
                                    <th>Motorcycle Model</th>
                                    <th>Plate</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${rides.map(r => `
                                    <tr>
                                        <td style="font-family: monospace; font-size: 11px;">${r.id.slice(0, 10)}...</td>
                                        <td style="font-weight: 700;">${r.driverName}</td>
                                        <td>${r.driverDept}</td>
                                        <td style="font-weight: 600;">${r.originName} ➔ ${r.destinationName}</td>
                                        <td>${r.departureTime ? r.departureTime.slice(11, 16) : '—'}</td>
                                        <td style="font-weight: 800; color: var(--primary);">৳${r.farePerSeat.toFixed(0)}</td>
                                        <td style="text-align: center; font-weight: bold;">${r.availableSeats}/${r.totalSeats}</td>
                                        <td>
                                            <span class="pill ${r.status === 'active' ? 'pill-green' : (r.status === 'completed' ? 'pill-blue' : (r.status === 'cancelled' ? 'pill-red' : 'pill-amber'))}">
                                                ${r.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td>${r.vehicleModel}</td>
                                        <td style="font-family: monospace;">${r.vehiclePlate || '—'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderBookingsTab(container) {
            const res = await fetch('/ride/api/admin/bookings');
            const bookings = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">📑 Passenger Booking Orders (${bookings.length})</div>
                        <div class="toolbar">
                            <input type="text" class="search-input" placeholder="Search passenger or pickup..." oninput="filterTableRows(this.value)">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=bookings', '_blank')">📥 Export CSV</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Booking ID</th>
                                    <th>Passenger</th>
                                    <th>Phone</th>
                                    <th>Pickup Point</th>
                                    <th>Drop-off Point</th>
                                    <th>Seats</th>
                                    <th>Total Fare</th>
                                    <th>Status</th>
                                    <th>Requested At</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${bookings.map(b => `
                                    <tr>
                                        <td style="font-family: monospace; font-size: 11px;">${b.id.slice(0, 12)}</td>
                                        <td style="font-weight: 700;">${b.passengerName}</td>
                                        <td>${b.passengerPhone || '—'}</td>
                                        <td>${b.pickupPoint}</td>
                                        <td>${b.dropoffPoint}</td>
                                        <td style="text-align: center; font-weight: bold;">${b.seatsBooked}</td>
                                        <td style="font-weight: 800; color: var(--primary);">৳${b.totalFare.toFixed(0)}</td>
                                        <td>
                                            <span class="pill ${b.status === 'accepted' ? 'pill-green' : (b.status === 'completed' ? 'pill-blue' : (b.status === 'cancelled' ? 'pill-red' : 'pill-amber'))}">
                                                ${b.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td style="font-size: 11px;">${b.requestedAt ? b.requestedAt.slice(0, 16).replace('T', ' ') : '—'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderCompletedTab(container) {
            const res = await fetch('/ride/api/admin/completed-rides');
            const trips = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🏁 Completed Trips & Full GPS Audit Trail (${trips.length})</div>
                        <div class="toolbar">
                            <button class="btn btn-secondary" onclick="window.open('/ride/api/admin/export/csv?type=completed', '_blank')">📥 Download Trips CSV</button>
                            <button class="btn btn-accent" onclick="window.open('/ride/api/admin/export/pdf?type=completed', '_blank')">🖨️ Printable PDF Audit</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Trip ID</th>
                                    <th>Biker / Driver</th>
                                    <th>Passenger</th>
                                    <th>Corridor (Route)</th>
                                    <th>Completed At</th>
                                    <th>Fare</th>
                                    <th>Start GPS</th>
                                    <th>End GPS</th>
                                    <th>Rating</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${trips.map(t => `
                                    <tr>
                                        <td style="font-family: monospace; font-size: 11px;">${t.id.slice(0, 12)}</td>
                                        <td style="font-weight: 700;">${t.driverName}</td>
                                        <td style="font-weight: 600;">${t.passengerName || 'Commuter'}</td>
                                        <td>${t.originName} ➔ ${t.destinationName}</td>
                                        <td style="font-size: 11.5px;">${t.completedTime ? t.completedTime.slice(0, 16).replace('T', ' ') : '—'}</td>
                                        <td style="font-weight: 800; color: var(--primary);">৳${t.fare.toFixed(0)}</td>
                                        <td>${t.startMapsLink ? `<a href="${t.startMapsLink}" target="_blank" style="color: var(--primary); font-weight: bold; text-decoration: underline;">📍 Maps Link</a>` : '—'}</td>
                                        <td>${t.endMapsLink ? `<a href="${t.endMapsLink}" target="_blank" style="color: var(--accent); font-weight: bold; text-decoration: underline;">🏁 Maps Link</a>` : '—'}</td>
                                        <td>⭐ ${t.rating}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderSosTab(container) {
            const res = await fetch('/ride/api/admin/sos-alerts');
            const alerts = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🚨 Campus Emergency SOS Alerts (${alerts.length})</div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Alert ID</th>
                                    <th>Student Name</th>
                                    <th>Student ID</th>
                                    <th>Phone</th>
                                    <th>Location Spot</th>
                                    <th>Coordinates</th>
                                    <th>Status</th>
                                    <th>Timestamp</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${alerts.length === 0 ? '<tr><td colspan="8" style="text-align: center; padding: 30px; color: var(--text-muted);">No emergency SOS alerts recorded. Campus is safe!</td></tr>' : ''}
                                ${alerts.map(a => `
                                    <tr>
                                        <td style="font-family: monospace;">${a.id}</td>
                                        <td style="font-weight: 700; color: var(--danger);">${a.studentName}</td>
                                        <td style="font-family: monospace;">${a.studentId}</td>
                                        <td style="font-weight: 600;">${a.studentPhone}</td>
                                        <td>${a.locationName}</td>
                                        <td style="font-family: monospace;">${a.latitude ? a.latitude.toFixed(4) + ', ' + a.longitude.toFixed(4) : '—'}</td>
                                        <td><span class="pill pill-red">${a.status.toUpperCase()}</span></td>
                                        <td>${a.createdAt.slice(0, 16).replace('T', ' ')}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderNoticesTab(container) {
            const res = await fetch('/ride/api/admin/notices');
            const notices = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">📢 University Authority Notices (${notices.length})</div>
                        <button class="btn btn-accent" onclick="openNoticeModal()">+ New Broadcast Notice</button>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Headline</th>
                                    <th>Content Message</th>
                                    <th>Target Audience</th>
                                    <th>Priority</th>
                                    <th>Issued By</th>
                                    <th>Broadcast Time</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${notices.length === 0 ? '<tr><td colspan="6" style="text-align: center; padding: 30px; color: var(--text-muted);">No notices broadcasted yet. Click "New Broadcast Notice" to send one.</td></tr>' : ''}
                                ${notices.map(n => `
                                    <tr>
                                        <td style="font-weight: 800; color: var(--text-main);">${n.title}</td>
                                        <td style="max-width: 380px;">${n.content}</td>
                                        <td><span class="pill pill-blue">${n.targetAudience.toUpperCase()}</span></td>
                                        <td><span class="pill ${n.priority === 'emergency' ? 'pill-red' : (n.priority === 'urgent' ? 'pill-amber' : 'pill-green')}">${n.priority.toUpperCase()}</span></td>
                                        <td style="font-size: 11.5px;">${n.adminEmail}</td>
                                        <td style="font-size: 11.5px; color: var(--text-muted);">${n.createdAt.slice(0, 16).replace('T', ' ')}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        async function renderAdminsTab(container) {
            const res = await fetch('/ride/api/admin/admins');
            const admins = await res.json();

            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div class="card-title">🛡️ Authority Administrators (${admins.length})</div>
                        <div class="toolbar">
                            <button class="btn btn-outline" style="color: var(--primary); border-color: var(--primary);" onclick="openPassModal()">🔑 Change Password</button>
                            <button class="btn btn-accent" onclick="openAddAdminModal()">➕ Add New Administrator</button>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Admin Email</th>
                                    <th>Full Name</th>
                                    <th>Role Privilege</th>
                                    <th>Status</th>
                                    <th>Account Created</th>
                                    <th>Last Login</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${admins.map(a => `
                                    <tr>
                                        <td style="font-weight: 800; font-family: monospace;">${a.email}</td>
                                        <td style="font-weight: 700;">${a.name}</td>
                                        <td><span class="pill pill-green">${a.role.toUpperCase()}</span></td>
                                        <td><span class="pill pill-blue">ACTIVE</span></td>
                                        <td style="font-size: 11px;">${a.createdAt ? a.createdAt.slice(0, 10) : '—'}</td>
                                        <td style="font-size: 11px;">${a.lastLogin || 'Never'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
            `;
        }

        // =================================================================
        // Action Handlers (Notices, Password, Admins)
        // =================================================================

        function openNoticeModal() { document.getElementById('noticeModal').style.display = 'flex'; }
        function openPassModal() {
            if (loggedInAdmin) document.getElementById('chgEmail').value = loggedInAdmin.email;
            document.getElementById('passModal').style.display = 'flex';
        }
        function openAddAdminModal() { document.getElementById('addAdminModal').style.display = 'flex'; }
        function closeModal(id) { document.getElementById(id).style.display = 'none'; }

        async function submitNotice() {
            const title = document.getElementById('notcTitle').value.trim();
            const content = document.getElementById('notcContent').value.trim();
            const targetAudience = document.getElementById('notcAudience').value;
            const priority = document.getElementById('notcPriority').value;

            if (!title || !content) {
                alert('Please enter both title and content.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/notices', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        title, content, targetAudience, priority,
                        adminEmail: loggedInAdmin?.email || '252-15-234@diu.edu.bd'
                    })
                });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to send notice');
                alert('✓ ' + d.message);
                closeModal('noticeModal');
                document.getElementById('notcTitle').value = '';
                document.getElementById('notcContent').value = '';
                if (currentTab === 'notices') switchTab('notices');
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        async function submitPasswordChange() {
            const email = document.getElementById('chgEmail').value.trim();
            const oldPassword = document.getElementById('chgOldPass').value;
            const newPassword = document.getElementById('chgNewPass').value;

            if (!email || !newPassword) {
                alert('Please fill email and new password.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/change-password', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, oldPassword, newPassword })
                });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to change password');
                alert('✓ ' + d.message);
                closeModal('passModal');
                document.getElementById('chgOldPass').value = '';
                document.getElementById('chgNewPass').value = '';
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        async function submitAddAdmin() {
            const name = document.getElementById('newAdmName').value.trim();
            const email = document.getElementById('newAdmEmail').value.trim();
            const password = document.getElementById('newAdmPass').value;
            const role = document.getElementById('newAdmRole').value;

            if (!name || !email || !password) {
                alert('All fields are required.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/create-admin', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name, email, password, role })
                });
                const d = await res.json();
                if (!res.ok) throw new Error(d.detail || 'Failed to add admin');
                alert('✓ ' + d.message);
                closeModal('addAdminModal');
                document.getElementById('newAdmName').value = '';
                document.getElementById('newAdmEmail').value = '';
                document.getElementById('newAdmPass').value = '';
                if (currentTab === 'admins') switchTab('admins');
            } catch(e) {
                alert('Error: ' + e.message);
            }
        }

        function filterTableRows(query) {
            const q = query.toLowerCase().trim();
            const rows = document.querySelectorAll('#dataTable tbody tr');
            rows.forEach(r => {
                const text = r.innerText.toLowerCase();
                r.style.display = text.includes(q) ? '' : 'none';
            });
        }

        // =================================================================
        // AI Assistant Settings Management
        // =================================================================

        async function renderAiAssistantTab(container) {
            container.innerHTML = `
                <div class="content-card">
                    <div class="card-header">
                        <div>
                            <div class="card-title">🤖 DIU Ride AI Companion & Prompt Control Center</div>
                            <div style="font-size: 12px; color: var(--text-muted); margin-top: 4px;">
                                Manage Groq Cloud LLM engine, customize the cordial student system prompt, edit app knowledge base, and test responses live.
                            </div>
                        </div>
                        <div class="toolbar">
                            <button class="btn btn-outline" onclick="resetAiPromptToDefault()">↺ Reset to Default Prompt</button>
                            <button class="btn btn-accent" onclick="saveAiSettingsFromAdmin()">💾 Save AI Settings</button>
                        </div>
                    </div>
                    <div style="padding: 24px; display: flex; flex-direction: column; gap: 24px;">
                        <div style="background: #EFF6FF; border: 1.5px solid #93C5FD; border-radius: 12px; padding: 14px 18px; color: #1E40AF; font-size: 13px; line-height: 1.5;">
                            💡 <strong>Realtime AI Control:</strong> Any edits made to the System Prompt, Model, or Knowledge Base are saved to the SQLite database and immediately update all student mobile chatboxes and web terminals in real time without needing to restart the server or recompile the app.
                        </div>

                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                            <!-- Left: Engine Config & Live Test Playground -->
                            <div style="display: flex; flex-direction: column; gap: 16px;">
                                <div style="border: 1px solid var(--border); border-radius: 12px; padding: 16px; background: white;">
                                    <h4 style="font-size: 14px; font-weight: 800; color: #1E293B; margin-bottom: 12px;">⚙️ Engine & API Configuration</h4>
                                    <div class="form-group" style="margin-bottom: 12px;">
                                        <label style="font-size: 12px; font-weight: 700;">Groq API Key</label>
                                        <input type="password" id="aiGroqKey" class="form-control" placeholder="gsk_..." style="font-family: monospace; font-size: 12px;" />
                                        <div style="display: flex; justify-content: flex-end; margin-top: 4px;">
                                            <button class="btn btn-outline" type="button" style="padding: 2px 8px; font-size: 11px;" onclick="toggleKeyVisibility()">Show / Hide Key</button>
                                        </div>
                                    </div>
                                    <div class="form-group" style="margin-bottom: 12px;">
                                        <label style="font-size: 12px; font-weight: 700;">Active AI Model</label>
                                        <input type="text" id="aiModelName" class="form-control" placeholder="openai/gpt-oss-120b" style="font-family: monospace; font-size: 12px;" />
                                        <span style="font-size: 11px; color: var(--text-muted); display: block; margin-top: 4px;">Recommended: openai/gpt-oss-120b, qwen/qwen3.8-27b, openai/gpt-oss-20b</span>
                                    </div>
                                    <div style="display: flex; align-items: center; gap: 8px; margin-top: 8px;">
                                        <span style="width: 10px; height: 10px; border-radius: 50%; background: #22C55E; display: inline-block;"></span>
                                        <span style="font-size: 12px; font-weight: 700; color: #166534;">Groq Cloud Proxy Connected & Ready</span>
                                    </div>
                                </div>

                                <!-- Live Interactive Playground -->
                                <div style="border: 1px solid var(--border); border-radius: 12px; padding: 16px; background: white;">
                                    <h4 style="font-size: 14px; font-weight: 800; color: var(--primary); margin-bottom: 10px;">🧪 Live AI Prompt Playground</h4>
                                    <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 12px;">
                                        Test how the AI greets students by name and sorts active rides/requests with your current prompt:
                                    </p>
                                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 10px;">
                                        <div>
                                            <label style="font-size: 11px; font-weight: 700;">Student Name</label>
                                            <input type="text" id="testAiStudentName" class="form-control" value="Rahat" style="font-size: 12px;" />
                                        </div>
                                        <div>
                                            <label style="font-size: 11px; font-weight: 700;">App Role</label>
                                            <select id="testAiRole" class="form-control" style="font-size: 12px;">
                                                <option value="passenger">Passenger (Commuter)</option>
                                                <option value="rider">Biker / Rider</option>
                                            </select>
                                        </div>
                                    </div>
                                    <div class="form-group" style="margin-bottom: 10px;">
                                        <label style="font-size: 11px; font-weight: 700;">Student Query / Message</label>
                                        <input type="text" id="testAiMessage" class="form-control" value="Mirpur 10 theke 9:30 AM e DSC jabo, kono biker ache?" style="font-size: 12px;" />
                                    </div>
                                    <button class="btn btn-secondary" style="width: 100%; margin-bottom: 12px;" onclick="runAdminAiTest()">🚀 Send Test Message & Evaluate</button>
                                    <div id="testAiResult" style="min-height: 120px; max-height: 250px; overflow-y: auto; background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px; padding: 12px; font-size: 12px; line-height: 1.5; color: #334155; white-space: pre-wrap;">
                                        <em>AI response will appear here...</em>
                                    </div>
                                </div>
                            </div>

                            <!-- Right: System Prompt & Knowledge Base -->
                            <div style="display: flex; flex-direction: column; gap: 16px;">
                                <div style="border: 1px solid var(--border); border-radius: 12px; padding: 16px; background: white;">
                                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                                        <h4 style="font-size: 14px; font-weight: 800; color: #1E293B;">📜 System Prompt (Editable)</h4>
                                        <span id="promptCharCount" style="font-size: 11px; color: var(--text-muted);">0 chars</span>
                                    </div>
                                    <p style="font-size: 11.5px; color: var(--text-muted); margin-bottom: 8px;">
                                        Instructs the AI on tone (polite, respectful, cordial), language style, greeting students by name, and matchmaking rules.
                                    </p>
                                    <textarea id="aiSystemPrompt" class="form-control" style="height: 220px; font-family: monospace; font-size: 11.5px; line-height: 1.45; resize: vertical;" oninput="updatePromptCount()"></textarea>
                                </div>

                                <div style="border: 1px solid var(--border); border-radius: 12px; padding: 16px; background: white;">
                                    <h4 style="font-size: 14px; font-weight: 800; color: #1E293B; margin-bottom: 8px;">📖 App Knowledge Base & Tutorial (README)</h4>
                                    <p style="font-size: 11.5px; color: var(--text-muted); margin-bottom: 8px;">
                                        App guidelines, campus landmarks, passenger/rider tutorials, and fuel sharing rules provided to the AI.
                                    </p>
                                    <textarea id="aiKnowledgeBase" class="form-control" style="height: 160px; font-family: monospace; font-size: 11.5px; line-height: 1.45; resize: vertical;"></textarea>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            `;

            loadAiSettingsIntoForm();
        }

        async function loadAiSettingsIntoForm() {
            try {
                const res = await fetch('/ride/api/admin/ai-settings');
                const data = await res.json();
                if (data.status === 'success' && data.settings) {
                    const s = data.settings;
                    if (document.getElementById('aiGroqKey')) document.getElementById('aiGroqKey').value = s.groq_api_key || '';
                    if (document.getElementById('aiModelName')) document.getElementById('aiModelName').value = s.model_name || '';
                    if (document.getElementById('aiSystemPrompt')) {
                        document.getElementById('aiSystemPrompt').value = s.system_prompt || '';
                        updatePromptCount();
                    }
                    if (document.getElementById('aiKnowledgeBase')) document.getElementById('aiKnowledgeBase').value = s.app_knowledge_base || '';
                }
            } catch (e) {
                console.error('Failed to load AI settings:', e);
            }
        }

        function toggleKeyVisibility() {
            const el = document.getElementById('aiGroqKey');
            if (el) {
                el.type = el.type === 'password' ? 'text' : 'password';
            }
        }

        function updatePromptCount() {
            const promptEl = document.getElementById('aiSystemPrompt');
            const countEl = document.getElementById('promptCharCount');
            if (promptEl && countEl) {
                countEl.innerText = `${promptEl.value.length} chars`;
            }
        }

        async function saveAiSettingsFromAdmin() {
            const groq_api_key = (document.getElementById('aiGroqKey')?.value || '').trim();
            const model_name = (document.getElementById('aiModelName')?.value || '').trim();
            const system_prompt = document.getElementById('aiSystemPrompt')?.value || '';
            const app_knowledge_base = document.getElementById('aiKnowledgeBase')?.value || '';

            if (!groq_api_key) {
                alert('Groq API Key is required.');
                return;
            }

            try {
                const res = await fetch('/ride/api/admin/ai-settings', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        groq_api_key,
                        model_name,
                        system_prompt,
                        app_knowledge_base
                    })
                });
                const data = await res.json();
                if (!res.ok) throw new Error(data.detail || 'Failed to save');
                alert('✓ ' + (data.message || 'AI Settings saved successfully!'));
            } catch (e) {
                alert('Error saving AI settings: ' + e.message);
            }
        }

        async function resetAiPromptToDefault() {
            if (!confirm('Are you sure you want to reset the system prompt to the default polite DIU Ride prompt?')) {
                return;
            }
            try {
                const res = await fetch('/ride/api/admin/ai-reset-prompt', { method: 'POST' });
                const data = await res.json();
                if (!res.ok) throw new Error(data.detail || 'Reset failed');
                alert('✓ ' + (data.message || 'Prompt reset successfully!'));
                await loadAiSettingsIntoForm();
            } catch (e) {
                alert('Error resetting prompt: ' + e.message);
            }
        }

        async function runAdminAiTest() {
            const user_name = (document.getElementById('testAiStudentName')?.value || 'Student').trim();
            const user_role = document.getElementById('testAiRole')?.value || 'passenger';
            const message = (document.getElementById('testAiMessage')?.value || '').trim();
            const resultBox = document.getElementById('testAiResult');

            if (!message) {
                alert('Please enter a query to test.');
                return;
            }

            resultBox.innerHTML = '<span style="color: var(--primary);">⏳ Consulting DIU Ride AI Companion...</span>';

            try {
                const startTime = Date.now();
                const res = await fetch('/ride/api/ai/chat', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ user_name, user_role, message, history: [] })
                });
                const data = await res.json();
                const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);

                if (!res.ok) throw new Error(data.detail || 'AI query error');

                resultBox.innerHTML = `<strong>🤖 AI Response (${elapsed}s | Model: ${data.model || 'Groq'}):</strong>\n\n${data.reply}`;
            } catch (e) {
                resultBox.innerHTML = `<span style="color: #DC2626;">❌ Error: ${e.message}</span>`;
            }
        }
    </script>
</body>
</html>
"""

@admin_router.api_route("/ride/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@admin_router.api_route("/ride/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
@admin_router.api_route("/admin", methods=["GET", "HEAD"], response_class=HTMLResponse)
@admin_router.api_route("/admin/", methods=["GET", "HEAD"], response_class=HTMLResponse)
def serve_admin_portal():
    return HTMLResponse(content=ADMIN_HTML)

