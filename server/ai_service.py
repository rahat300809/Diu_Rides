import os
import json
import base64
import sqlite3
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional

def get_default_groq_key() -> str:
    env_k = os.getenv("GROQ_API_KEY")
    if env_k and env_k.strip():
        return env_k.strip()
    cfg = os.path.join(os.path.dirname(__file__), "ai_config.json")
    if os.path.exists(cfg):
        try:
            with open(cfg, "r", encoding="utf-8") as f:
                d = json.load(f)
                if d.get("groq_api_key"):
                    return d["groq_api_key"].strip()
        except Exception:
            pass
    return ""

DEFAULT_GROQ_API_KEY = get_default_groq_key()
DEFAULT_MODEL_NAME = "openai/gpt-oss-120b"
FALLBACK_MODELS = ["qwen/qwen3.8-27b", "openai/gpt-oss-20b"]

DEFAULT_SYSTEM_PROMPT = """You are "DIU Ride AI Assistant" (ডিআইইউ রাইড সহকারী) — an exceptionally courteous, warm, respectful, caring, and intelligent campus assistant built exclusively for students, teachers, and commuters of Daffodil International University (DIU).

### Core Demeanor & Personality:
1. **Unmatched Politeness & Cordiality**: Always speak with the utmost respect, brotherly/sisterly affection, and warmth. Use polite respectful Bengali phrases (e.g. "আসসালামু আলাইকুম [নাম] ভাইয়া/আপু! 🌸", "আপনার দিনটি অনেক সুন্দর ও বরকতময় কাটুক", "আপনার যাত্রা নিরাপদ হোক", "আমি আপনাকে কীভাবে সাহায্য করতে পারি?").
2. **Loving & Caring Campus Companion**: Treat students affectionately like dear university peers. Never be robotic, brief, or cold. Be cheerful, helpful, patient, and polite.
3. **Language**: Naturally answer in polite Bengali (বাংলা), English, or Banglish depending on how the student writes, but ALWAYS keep the tone heartfelt, respectful, and cordial.

### Core Capabilities:
1. **Personalized Greetings**:
   - Always address the student by their name respectfully (e.g. "রাহাত ভাইয়া" / "তনিমা আপু") when their name is known.
2. **App Guidance & Tutorial**:
   - Provide clear, friendly instructions on how to use DIU Ride:
     - How to find and book rides as a Passenger.
     - How to publish rides and split fuel as a Biker / Rider.
     - How to post / throw a custom "Schedule / Ride Request" if no direct ride matches their time.
     - How to use 1-on-1 private messaging safely.
     - How to use the red Emergency SOS button and live GPS tracking.
     - Fair fuel sharing rates (typically 30-80 BDT for campus commute).
3. **Trip & Route Matching Agent**:
   - When a student asks to find a ride (Passenger) or find passengers (Rider):
     - Carefully check the LIVE ACTIVE RIDES and LIVE PASSENGER REQUESTS provided in the system context.
     - Compare origin, destination, corridor, and requested timeframe.
     - Suggest the best matching rides/requests sorted by closest departure time.
     - Mention biker name, bike model, departure time, fare, and available seats.
     - If no exact time match exists, warmly present the nearest available time slot, and guide them to tap "Schedule / Throw request" so riders can accept them.
4. **Safety & Ethics First**:
   - Gently remind riders and passengers about wearing helmets, punctuality, and mutual respect among varsity classmates.
"""

def get_default_knowledge_base() -> str:
    kb_path = os.path.join(os.path.dirname(__file__), "APP_AI_KNOWLEDGE_BASE.md")
    if os.path.exists(kb_path):
        try:
            with open(kb_path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception:
            pass
    return """# DIU Ride Guidelines
DIU Ride is an exclusive peer-to-peer campus ride sharing network for Daffodil International University (DIU) students and staff.
- Passenger Mode: Search and book departing bikes, or schedule custom ride requests.
- Rider Mode: Offer seats to split fuel (30-80 BDT), view student requests, and track confirmations.
- Safety: SOS emergency button, live GPS tracking, and verified varsity community.
"""

def init_ai_settings_table(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS ai_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    """)

    now = datetime.now(timezone.utc).isoformat()
    defaults = {
        "groq_api_key": DEFAULT_GROQ_API_KEY,
        "model_name": DEFAULT_MODEL_NAME,
        "system_prompt": DEFAULT_SYSTEM_PROMPT,
        "app_knowledge_base": get_default_knowledge_base(),
    }

    for k, v in defaults.items():
        cursor.execute("SELECT key FROM ai_settings WHERE key = ?", (k,))
        if not cursor.fetchone():
            cursor.execute("INSERT INTO ai_settings (key, value, updated_at) VALUES (?, ?, ?)", (k, v, now))

    conn.commit()

def get_all_ai_settings(conn: sqlite3.Connection) -> Dict[str, str]:
    cursor = conn.cursor()
    cursor.execute("SELECT key, value FROM ai_settings")
    rows = cursor.fetchall()
    settings = {r[0]: r[1] for r in rows}
    if "groq_api_key" not in settings:
        settings["groq_api_key"] = DEFAULT_GROQ_API_KEY
    if "model_name" not in settings:
        settings["model_name"] = DEFAULT_MODEL_NAME
    if "system_prompt" not in settings:
        settings["system_prompt"] = DEFAULT_SYSTEM_PROMPT
    if "app_knowledge_base" not in settings:
        settings["app_knowledge_base"] = get_default_knowledge_base()
    return settings

def save_ai_settings(conn: sqlite3.Connection, settings: Dict[str, str]) -> Dict[str, str]:
    cursor = conn.cursor()
    now = datetime.now(timezone.utc).isoformat()
    for k, v in settings.items():
        cursor.execute("""
        INSERT INTO ai_settings (key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """, (k, str(v), now))
    conn.commit()
    return get_all_ai_settings(conn)

def call_groq_chat(api_key: str, model: str, messages: List[Dict[str, str]], max_tokens: int = 800) -> str:
    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.5,
    }
    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data_bytes,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "DIU-Ride-AI/1.0",
        }
    )

    with urllib.request.urlopen(req, timeout=14) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        choices = res.get("choices", [])
        if choices:
            msg = choices[0].get("message", {})
            content = msg.get("content") or ""
            if not content.strip() and "reasoning" in msg:
                content = msg.get("reasoning") or ""
            return content.strip()
    return ""

def process_ai_chat_request(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
    user_id = payload.get("user_id") or ""
    user_name = (payload.get("user_name") or "Student").strip()
    user_role = (payload.get("user_role") or "passenger").strip().lower()
    message = (payload.get("message") or "").strip()
    history = payload.get("history") or []

    settings = get_all_ai_settings(conn)
    api_key = settings.get("groq_api_key", DEFAULT_GROQ_API_KEY).strip()
    primary_model = settings.get("model_name", DEFAULT_MODEL_NAME).strip()
    system_prompt = settings.get("system_prompt", DEFAULT_SYSTEM_PROMPT)
    knowledge_base = settings.get("app_knowledge_base", "")

    # Query active published rides
    cursor = conn.cursor()
    cursor.execute("""
    SELECT id, driver_name, driver_dept, driver_phone, origin_name, destination_name,
           waypoint_name, departure_time, fare_per_seat, available_seats, vehicle_model,
           route_corridor
    FROM rides
    WHERE status = 'published' AND available_seats > 0
    ORDER BY departure_time ASC
    LIMIT 15
    """)
    active_rides = [dict(r) for r in cursor.fetchall()]

    # Query open passenger requests
    cursor.execute("""
    SELECT id, passenger_name, passenger_dept, passenger_phone, pickup, dropoff,
           requested_time, proposed_fare, notes
    FROM passenger_requests
    WHERE status = 'open'
    ORDER BY created_at DESC
    LIMIT 15
    """)
    active_requests = [dict(r) for r in cursor.fetchall()]

    # Format live database context
    rides_summary = ""
    if active_rides:
        rides_lines = []
        for r in active_rides:
            rides_lines.append(
                f"- [Ride ID: {r['id']}] Driver: {r['driver_name']} ({r.get('driver_dept') or 'Student'}) | "
                f"From: {r['origin_name']} -> To: {r['destination_name']} | "
                f"Departure Time: {r['departure_time']} | Fare: {r['fare_per_seat']} BDT | "
                f"Seats: {r['available_seats']} | Bike: {r['vehicle_model']}"
            )
        rides_summary = "\n".join(rides_lines)
    else:
        rides_summary = "No published rides currently available in the database."

    requests_summary = ""
    if active_requests:
        req_lines = []
        for q in active_requests:
            req_lines.append(
                f"- [Req ID: {q['id']}] Passenger: {q['passenger_name']} ({q.get('passenger_dept') or 'Student'}) | "
                f"Pickup: {q['pickup']} -> Dropoff: {q['dropoff']} | "
                f"Requested Time: {q['requested_time']} | Proposed Fare: {q['proposed_fare']} BDT"
            )
        requests_summary = "\n".join(req_lines)
    else:
        requests_summary = "No open student passenger requests currently listed."

    # BD Current time calculation (UTC+6)
    bd_now = datetime.now(timezone(timedelta(hours=6))).strftime("%Y-%m-%d %I:%M %p")

    composed_system_prompt = f"""{system_prompt}

### CURRENT OPERATIONAL CONTEXT:
- Current Local Time (Bangladesh): {bd_now}
- Interacting Student Name: {user_name}
- Student Current App Mode: {"Biker / Rider (Motorbike Owner)" if user_role == "rider" else "Passenger (Commuter)"}

### OFFICIAL APP KNOWLEDGE BASE & TUTORIAL:
{knowledge_base}

### LIVE ACTIVE PUBLISHED BIKER RIDES (From Database):
{rides_summary}

### LIVE ACTIVE OPEN PASSENGER REQUESTS (From Database):
{requests_summary}

### INSTRUCTIONS FOR MATCHING & RESPONSE:
1. Always greet {user_name} with brotherly/sisterly affection, honor, and warm cordiality (e.g., 'আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸').
2. If they ask how to use the app, provide a structured, polite breakdown based on the Official Knowledge Base.
3. If they are looking for a ride to/from campus, check the LIVE ACTIVE PUBLISHED BIKER RIDES. Sort and recommend the closest departure times for their route. Mention driver name, bike model, time, and fare.
4. If no exact ride matches their route or timeframe, politely let them know and advise them to click 'Schedule / Throw request' to post their own route and time so passing bikers can accept them.
5. If they are a Biker looking for passengers, check the LIVE ACTIVE OPEN PASSENGER REQUESTS and recommend matching students.
6. Always maintain genuine warmth, politeness, and university community brotherhood.
"""

    # Build messages sequence
    messages = [{"role": "system", "content": composed_system_prompt}]

    # Include recent chat history (up to last 6 messages)
    if isinstance(history, list):
        for h in history[-6:]:
            r = h.get("role")
            c = h.get("content")
            if r in ("user", "assistant") and c:
                messages.append({"role": r, "content": str(c)})

    # Append current message
    messages.append({"role": "user", "content": message})

    reply = ""
    used_model = primary_model

    # Try primary model first, fallback if error
    models_to_try = [primary_model] + [m for m in FALLBACK_MODELS if m != primary_model]
    last_error = None

    for m in models_to_try:
        try:
            reply = call_groq_chat(api_key, m, messages)
            if reply and reply.strip():
                used_model = m
                break
        except Exception as e:
            last_error = e
            print(f"[GROQ CHAT ATTEMPT FAILED] Model: {m}, Error: {e}")

    # If all models failed or offline, provide a respectful fallback response
    if not reply or not reply.strip():
        print(f"[GROQ CHAT ALL FAILED] Last error: {last_error}")
        if active_rides and user_role != "rider":
            top_rides = "\n".join([f"• {r['origin_name']} ➔ {r['destination_name']} ({r['departure_time']}, {r['driver_name']}, {r['fare_per_seat']} ৳)" for r in active_rides[:3]])
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸 সাময়িক সার্ভার বিলম্বের জন্য আন্তরিকভাবে দুঃখিত। "
                f"বর্তমানে আমাদের সিস্টেমে এই রাইডগুলো সক্রিয় রয়েছে:\n\n{top_rides}\n\n"
                f"আপনার পছন্দের রুটের রাইড বুক করতে অ্যাপের হোমস্ক্রিন ব্যবহার করুন, অথবা আপনার সুবিধাজনক সময়ের জন্য 'Schedule' অপশনে রিকোয়েস্ট পোস্ট করুন।"
            )
        else:
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸 আপনার সাথে যুক্ত হতে পেরে আমি অত্যন্ত আনন্দিত। "
                f"ডিআইইউ রাইড শেয়ারিং সম্পর্কিত যেকোনো জিজ্ঞাসা বা রুট সংক্রান্ত তথ্যের জন্য আমি সর্বদা আপনার সেবায় প্রস্তুত আছি। "
                f"আপনি কোথা থেকে ক্যাম্পাসে যেতে চান বা কোনো নির্দিষ্ট সময়ে রাইড খুঁজছেন কি না জানালে আমি তৎক্ষণাৎ সাহায্য করব।"
            )

    # Match relevant rides/requests to return structured data for rich UI cards
    matched_rides = []
    matched_requests = []
    lower_msg = message.lower()

    if active_rides:
        for r in active_rides:
            orig = (r.get("origin_name") or "").lower()
            dest = (r.get("destination_name") or "").lower()
            corr = (r.get("route_corridor") or "").lower()
            # If user mentioned key places or asked for general rides
            if any(term in lower_msg for term in ["all", "sob", "dekhao", "ride", "biker", "bike"]) or \
               any(k in lower_msg for k in orig.split() if len(k) > 2) or \
               any(k in lower_msg for k in dest.split() if len(k) > 2) or \
               any(k in lower_msg for k in corr.split() if len(k) > 2):
                matched_rides.append(r)
                if len(matched_rides) >= 3:
                    break

    if active_requests and user_role == "rider":
        for q in active_requests:
            pickup = (q.get("pickup") or "").lower()
            dropoff = (q.get("dropoff") or "").lower()
            if any(term in lower_msg for term in ["passenger", "request", "iatri", "student"]) or \
               any(k in lower_msg for k in pickup.split() if len(k) > 2) or \
               any(k in lower_msg for k in dropoff.split() if len(k) > 2):
                matched_requests.append(q)
                if len(matched_requests) >= 3:
                    break

    return {
        "status": "success",
        "reply": reply,
        "model": used_model,
        "matched_rides": matched_rides,
        "matched_requests": matched_requests,
    }
