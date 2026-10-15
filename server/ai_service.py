import os
import json
import base64
import sqlite3
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional

from active_rides_manager import (
    get_active_rides_from_file,
    get_active_rides_for_ai,
    ACTIVE_RIDES_JSON_PATH,
    ACTIVE_RIDES_MD_PATH,
)

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
2. **Live Active Posted Rides (Read Directly From File)**:
   - You have direct, real-time read access to the LIVE POSTED RIDES file (`active_rides_data.json`).
   - Every ride in this file contains the latest active, non-expired posted rides with available seats.
   - When a student asks about rides, bikers, or traveling between locations:
     - Carefully check the LIVE ACTIVE POSTED RIDES listed in your context.
     - Match their route, corridor, and time.
     - Provide the biker's name, bike model, departure time, fare, and available seats.
     - If no exact match exists, explain politely and advise them to use the "Schedule / Throw Request" feature so passing bikers can see their request.
3. **App Guidance & Tutorial**:
   - Guide students on how to search and book rides, publish rides to split fuel, use private messaging, and access the Emergency SOS button.
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
        "temperature": 0.4,
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

    # 8-second snappy timeout to prevent client app freezes
    with urllib.request.urlopen(req, timeout=8) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        choices = res.get("choices", [])
        if choices:
            msg = choices[0].get("message", {})
            content = msg.get("content") or ""
            if not content.strip() and "reasoning" in msg:
                content = msg.get("reasoning") or ""
            return content.strip()
    return ""

def normalize_bangla_query(text: str) -> str:
    """Translates common Bengali location words and commute keywords to English tokens for matching."""
    t = text.lower()
    replacements = {
        "মিরপুর": " mirpur ",
        "আশুলিয়া": " ashulia ",
        "আশুলিয়া": " ashulia ",
        "উত্তরা": " uttara ",
        "ধানমন্ডি": " dhanmondi ",
        "বিরুলিয়া": " birulia ",
        "বিরুলিয়া": " birulia ",
        "ফার্মগেট": " farmgate ",
        "ক্যাম্পাস": " campus dsc ",
        "ডিএসসি": " dsc ",
        "স্মার্ট সিটি": " smart city ",
        "বাইক": " bike biker ",
        "বাইকার": " biker ",
        "রাইড": " ride ",
        "যাত্রী": " passenger ",
        "সব": " all ",
        "দেখাও": " show all ",
        "আসে": " ride ",
        "যাব": " ride ",
    }
    for bn, en in replacements.items():
        t = t.replace(bn, en)
    return t

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

    # DIRECT READ FROM FILE: Get all live active rides directly from active_rides_data.json
    active_rides = get_active_rides_from_file()
    rides_summary = get_active_rides_for_ai()

    # Query open passenger requests from database
    cursor = conn.cursor()
    cursor.execute("""
    SELECT id, passenger_name, passenger_dept, passenger_phone, pickup, dropoff,
           requested_time, proposed_fare, notes
    FROM passenger_requests
    WHERE status = 'open'
    ORDER BY created_at DESC
    LIMIT 15
    """)
    active_requests = [dict(r) for r in cursor.fetchall()]

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
- Realtime Storage Source: {os.path.basename(ACTIVE_RIDES_JSON_PATH)} (Live File on Server Disk)

### OFFICIAL APP KNOWLEDGE BASE & TUTORIAL:
{knowledge_base}

### LIVE ACTIVE POSTED RIDES (READ DIRECTLY FROM active_rides_data.json):
{rides_summary}

### LIVE ACTIVE OPEN PASSENGER REQUESTS:
{requests_summary}

### INSTRUCTIONS FOR MATCHING & RESPONSE:
1. Always greet {user_name} with brotherly/sisterly affection, honor, and warm cordiality (e.g., 'আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸').
2. Carefully inspect the LIVE ACTIVE POSTED RIDES above read directly from the persistent active rides file.
3. If they are looking for a ride to/from campus, compare the origin and destination of the posted rides. Mention the biker's name, department, bike model, departure time, fare, and available seats.
4. If no posted ride matches their route or timeframe, politely let them know and warmly recommend tapping 'Schedule / Throw request' so passing bikers can accept them.
5. If they are a Biker looking for passengers, check the LIVE ACTIVE OPEN PASSENGER REQUESTS and recommend matching students.
6. Maintain brotherly warmth, politeness, and university community solidarity.
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

    # Match relevant rides/requests to return rich interactive UI cards
    matched_rides = []
    matched_requests = []
    normalized_msg = normalize_bangla_query(message)
    lower_msg = message.lower() + " " + normalized_msg

    if active_rides:
        is_general_query = any(term in lower_msg for term in ["all", "sob", "dekhao", "show", "ride", "biker", "bike", "kono ride", "ache"])
        for r in active_rides:
            orig = (r.get("origin_name") or "").lower()
            dest = (r.get("destination_name") or "").lower()
            corr = (r.get("route_corridor") or "").lower()

            orig_tokens = [k for k in orig.split() if len(k) > 2]
            dest_tokens = [k for k in dest.split() if len(k) > 2]
            corr_tokens = [k for k in corr.split() if len(k) > 2]

            matched = (
                is_general_query or
                any(k in lower_msg for k in orig_tokens) or
                any(k in lower_msg for k in dest_tokens) or
                any(k in lower_msg for k in corr_tokens)
            )

            if matched:
                # Return complete formatted dictionary for Flutter client
                matched_rides.append({
                    "id": r["id"],
                    "driver_id": r["driver_id"],
                    "driver_name": r["driver_name"],
                    "driver_dept": r.get("driver_dept", "Student"),
                    "driver_phone": r.get("driver_phone", ""),
                    "driver_rating": r.get("driver_rating", 5.0),
                    "origin_name": r["origin_name"],
                    "origin_lat": r.get("origin_lat", 23.8765),
                    "origin_lng": r.get("origin_lng", 90.3204),
                    "destination_name": r["destination_name"],
                    "destination_lat": r.get("destination_lat", 23.8728),
                    "destination_lng": r.get("destination_lng", 90.3984),
                    "departure_time": r.get("departure_time_formatted") or r.get("departure_time"),
                    "raw_departure_time": r.get("departure_time"),
                    "fare_per_seat": r.get("fare_per_seat", 50.0),
                    "available_seats": r.get("available_seats", 1),
                    "total_seats": r.get("total_seats", 1),
                    "vehicle_model": r.get("vehicle_model", "Motorbike"),
                    "vehicle_plate": r.get("vehicle_plate", ""),
                    "route_corridor": r.get("route_corridor", "Campus Highway"),
                    "is_female_only": r.get("is_female_only", False),
                })
                if len(matched_rides) >= 4:
                    break

    # If all models failed or offline, generate an intelligent, live file-backed fallback response
    if not reply or not reply.strip():
        print(f"[GROQ CHAT ALL FAILED] Last error: {last_error}")
        if matched_rides and user_role != "rider":
            top_rides_lines = []
            for r in matched_rides[:3]:
                female_txt = " (মহিলাদের জন্য সংরক্ষিত)" if r.get("is_female_only") else ""
                top_rides_lines.append(
                    f"• **{r['origin_name']} ➔ {r['destination_name']}**\n"
                    f"  রাইডার: {r['driver_name']} ({r['vehicle_model']}) | সময়: {r['departure_time']} | ভাড়া: ৳{r['fare_per_seat']:.0f} (সিট: {r['available_seats']}টি ফাঁকা){female_txt}"
                )
            top_rides = "\n\n".join(top_rides_lines)
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸\n\n"
                f"আমাদের লাইভ রাইডস ফাইল (`active_rides_data.json`) থেকে এই মুহূর্তে সক্রিয় রাইডসমূহ পাওয়া গেছে:\n\n"
                f"{top_rides}\n\n"
                f"আপনি নিচের কার্ড থেকে সরাসরি **'বুক করুন'** বাটনে ট্যাপ করে সিট রিজার্ভ করতে পারেন।"
            )
        elif active_rides and user_role != "rider":
            top_rides = "\n".join([f"• {r['origin_name']} ➔ {r['destination_name']} (সময়: {r['departure_time_formatted']}, চালক: {r['driver_name']}, ভাড়া: ৳{r['fare_per_seat']:.0f})" for r in active_rides[:3]])
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸\n\n"
                f"বর্তমানে সিস্টেমে এই রাইডগুলো সক্রিয় রয়েছে:\n\n{top_rides}\n\n"
                f"আপনার সুবিধাজনক রুট ও সময়ের জন্য হোমস্ক্রিন ব্যবহার করুন অথবা 'Schedule' অপশনে রিকোয়েস্ট পোস্ট করুন।"
            )
        else:
            reply = (
                f"আসসালামু আলাইকুম {user_name} ভাইয়া/আপু! 🌸 আপনার সাথে যুক্ত হতে পেরে আমি অত্যন্ত আনন্দিত।\n\n"
                f"বর্তমানে আমাদের সিস্টেমে আপনার কাঙ্ক্ষিত রুটে কোনো সক্রিয় রাইড পোস্ট করা নেই। "
                f"আপনি অ্যাপের হোমপেইজ থেকে **'Schedule / Throw Request'** অপশনে আপনার রুট ও সময় পোস্ট করে রাখুন, "
                f"যাতে কোনো বাইকার ভাইয়া বা সহপাঠী ক্যাম্পাসে যাওয়ার পথে আপনার রিকোয়েস্ট গ্রহণ করতে পারেন।"
            )

    if active_requests and user_role == "rider":
        for q in active_requests:
            pickup = (q.get("pickup") or "").lower()
            dropoff = (q.get("dropoff") or "").lower()
            if any(term in lower_msg for term in ["passenger", "request", "iatri", "student", "all", "sob"]) or \
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
        "active_rides_file": os.path.basename(ACTIVE_RIDES_JSON_PATH),
        "total_active_rides_in_file": len(active_rides),
    }
