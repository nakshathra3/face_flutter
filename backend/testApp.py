from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import json
import base64
import cv2
import os
import sys
import warnings
from datetime import datetime, timedelta
from deepface import DeepFace
import threading
import time
import requests
import pytz
import logging
import contextlib

# --- CONFIGURATION ---
# SPEED UPDATE: "ssd" is ~10x faster than RetinaFace.
# If you get errors, change to "opencv" (fastest) or "mtcnn" (slower).
DETECTOR_BACKEND = "ssd" 
MODEL_NAME = "Facenet"
DISTANCE_THRESHOLD = 0.7
SIMILARITY_THRESHOLD = 0.73

# --- LOGGING SETUP ---
# Suppress lz4 and tensorflow warnings
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
logging.getLogger('lz4').setLevel(logging.CRITICAL)
warnings.filterwarnings('ignore')

@contextlib.contextmanager
def suppress_stderr():
    """Context manager to suppress stderr output (keeps console clean)."""
    with open(os.devnull, 'w') as devnull:
        old_stderr = sys.stderr
        try:
            sys.stderr = devnull
            yield
        finally:
            sys.stderr = old_stderr

app = Flask(__name__)
CORS(app)

# --- FILE PATHS & GLOBALS ---
EMPLOYEE_FILE = "employees.json"
ATTENDANCE_FILE = "attendance.json"
url = "https://workforce.dsignzmedia.com/api"
IST = pytz.timezone('Asia/Kolkata')

# --- HELPER FUNCTIONS ---

def ensure_file(path, default):
    if not os.path.exists(path):
        with open(path, "w") as f:
            json.dump(default, f, indent=2)

def load_json(path):
    try:
        if not os.path.exists(path):
            default_data = {"employees": []} if "employees" in path else {"records": []}
            with open(path, "w") as f: json.dump(default_data, f, indent=2)
            return default_data
        with open(path, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"❌ Error loading {path}: {e}")
        return {"employees": []} if "employees" in path else {"records": []}

def save_json(path, data):
    try:
        with open(path, "w") as f: json.dump(data, f, indent=2)
    except Exception as e:
        print(f"❌ Error saving {path}: {e}")

def get_ist_now():
    return datetime.now(IST)

def fetchAttendance():
    try:
        response = requests.get(url + "/active", timeout=5)
        if response.status_code == 200:
            data = response.json()
            data_content = data.get('data', {})
            employees = data_content.get('employees', [])
            interns = data_content.get('interns', [])
            return [*employees, *interns]
        else:
            return load_json(ATTENDANCE_FILE).get("records", [])
    except Exception as e:
        print(f"⚠️ API Fetch failed: {e}")
        return load_json(ATTENDANCE_FILE).get("records", [])

def base64_to_cv2(b64_string):
    try:
        if "," in b64_string:
            b64_string = b64_string.split(",")[1]
        img_bytes = base64.b64decode(b64_string)
        np_arr = np.frombuffer(img_bytes, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        return img
    except Exception as e:
        print(f"❌ Error decoding base64: {e}")
        return None

def cosine_similarity(a, b):
    if a is None or b is None: return -1.0
    a, b = np.array(a), np.array(b)
    if np.linalg.norm(a) == 0 or np.linalg.norm(b) == 0: return -1.0
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))

# --- OPTIMIZED AI FUNCTIONS (The Speed Fix) ---

def check_liveness_fast(img):
    """
    Lightning fast liveness check using blur/texture detection (0.002s).
    Rejects screens and flat photos which are usually smoother/blurrier than real faces.
    """
    try:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        variance = cv2.Laplacian(gray, cv2.CV_64F).var()
        # Threshold < 50 usually indicates a screen or very blurry image
        if variance < 50: 
            print(f"🚫 Liveness Fail: Variance {variance:.2f} (Too blurry/flat)")
            return False, "Image too blurry or flat (possible screen)"
        return True, "Live"
    except:
        return True, "Live" # Default to allow if check fails

def analyze_face_pipeline(img):
    """
    OPTIMIZED PIPELINE: Detects face ONCE.
    LOGIC UPDATE: Aggressive Neutral Suppression.
    If 'Neutral' is not overwhelming (>80%), we pick the next best emotion.
    """
    print("⚡ [PIPELINE] Starting optimized analysis...")
    sys.stdout.flush()
    try:
        # 1. Detect Face (SSD)
        with suppress_stderr():
            face_objs = DeepFace.extract_faces(
                img_path=img,
                detector_backend=DETECTOR_BACKEND,
                enforce_detection=True,
                align=True
            )
        
        if not face_objs:
            return None, None, "No face detected"

        # 2. Fix Image Format (RGB Float -> BGR Uint8)
        detected_face = face_objs[0]["face"] 
        if detected_face.max() <= 1.0:
            detected_face_uint8 = (detected_face * 255).astype(np.uint8)
        else:
            detected_face_uint8 = detected_face.astype(np.uint8)

        detected_face_bgr = cv2.cvtColor(detected_face_uint8, cv2.COLOR_RGB2BGR)

        # 3. Get Embedding
        with suppress_stderr():
            embedding_objs = DeepFace.represent(
                img_path=detected_face, 
                model_name=MODEL_NAME,
                detector_backend="skip",
                enforce_detection=False,
                normalization="base"
            )
        embedding = np.array(embedding_objs[0]["embedding"])

        # 4. Get Emotion
        with suppress_stderr():
            emotion_objs = DeepFace.analyze(
                img_path=detected_face_bgr, 
                actions=['emotion'],
                detector_backend="skip",
                enforce_detection=False
            )
        
        if isinstance(emotion_objs, list):
            result = emotion_objs[0]
        else:
            result = emotion_objs
            
        # --- AGGRESSIVE ANTI-NEUTRAL LOGIC ---
        emotions = result.get('emotion', {})
        
        # 1. Separate Neutral from the rest
        neutral_score = emotions.get('neutral', 0)
        other_emotions = {k: v for k, v in emotions.items() if k != 'neutral'}
        
        # 2. Find the strongest non-neutral emotion (The "Runner Up")
        runner_up_emotion = max(other_emotions, key=other_emotions.get)
        runner_up_score = other_emotions[runner_up_emotion]

        print(f"📊 [SCORES] Neutral: {neutral_score:.1f}% | Best Other: {runner_up_emotion.upper()} ({runner_up_score:.1f}%)")

        # 3. THE DECISION:
        # If the runner-up is significant (> 10%), pick it unless Neutral is overwhelming (> 80%).
        # This fixes cases like: Neutral 41%, Angry 37% -> Result: ANGRY.
        
        if neutral_score < 85.0 and runner_up_score > 5.0:
            top_emotion = runner_up_emotion
            print(f"💡 [LOGIC] Suppressed Neutral. Picked: {top_emotion}")
        else:
            top_emotion = 'neutral'
            print(f"💡 [LOGIC] Face is overwhelmingly neutral ({neutral_score:.1f}%)")

        print(f"✅ [PIPELINE] Final Emotion: {top_emotion}")
        return embedding, top_emotion, None

    except Exception as e:
        print(f"❌ [PIPELINE] Error: {e}")
        return None, None, str(e)

# --- ROUTES ---

@app.route("/test", methods=["GET", "POST"])
def test():
    return jsonify({"message": "Test endpoint working", "method": request.method})

@app.route("/enroll", methods=["POST"])
def enroll():
    print('='*60 + "\n🚀 [ENROLL] Request Received")
    data = request.get_json(force=True, silent=True)
    
    if not data or "face" not in data:
        return jsonify({"error": "No image provided"}), 400

    img = base64_to_cv2(data["face"])
    if img is None:
        return jsonify({"error": "Invalid image"}), 400

    # 1. Fast Liveness Check
    is_live, reason = check_liveness_fast(img)
    if not is_live:
        return jsonify({"success": False, "message": f"Security Check Failed: {reason}"}), 400

    # 2. Get Embedding
    embedding, _, error = analyze_face_pipeline(img)
    
    if error or embedding is None:
        return jsonify({"success": False, "message": "Face not detected clearly. Please retry."}), 400

    # 3. Determine User Type (ROBUST LOGIC)
    # Checks input first, then falls back to ID prefix check
    user_type = data.get("user_type")
    employee_id = data.get("employee_id", "")

    if not user_type: # If null, None, or empty string
        if employee_id.startswith("INT"):
            user_type = "intern"
        else:
            user_type = "employee"
            
    print(f"👤 [ENROLL] User Type determined: {user_type} (ID: {employee_id})")

    # 4. Save Data
    try:
        values = {
            "user_id": data["uuid"],
            "name": data["name"],
            "embedding": embedding.tolist(),
            "user_type": user_type  # Now guaranteed to be valid
        }
        
        print(f"🌐 [ENROLL] Sending to API: {url + '/face/enroll'}")
        response = requests.post(url + "/face/enroll", json=values, timeout=10)
        
        # Check API Response
        if response.status_code == 200:
            return jsonify({"success": True, "message": "Employee enrolled successfully"})
        else:
            # Pass the actual API error back for debugging
            print(f"❌ API Error: {response.text}")
            return jsonify({"success": False, "message": f"API Error: {response.text}"}), 500

    except Exception as e:
        print(f"❌ Enroll Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

@app.route("/recognize", methods=["POST"])
def recognize():
    print("\n" + "="*60)
    print("🚀 [RECOGNIZE] Processing Request...")
    sys.stdout.flush()
    start_time = time.time()

    try:
        data = request.get_json(force=True, silent=True)
        if not data or "image" not in data:
            return jsonify({"matched": False, "message": "Missing image"}), 400

        action = data.get("action")
        confirm = data.get("confirm", True)
        
        # 1. Decode Image
        img = base64_to_cv2(data["image"])
        if img is None:
            return jsonify({"matched": False, "message": "Invalid image"}), 400

        # 2. Fast Liveness Check
        is_live, reason = check_liveness_fast(img)
        # if not is_live: return jsonify({"matched": False, "message": reason}), 400

        # 3. AI Analysis
        live_embedding, emotion, error = analyze_face_pipeline(img)
        
        if error:
            return jsonify({"matched": False, "message": f"Face error: {error}"}), 400

        # 4. Fetch Employees
        employees = fetchAttendance()
        if not employees:
            return jsonify({"matched": False, "message": "No employees found"}), 400

        # 5. Find Best Match
        best_match = None
        best_score = -1

        for emp in employees:
            stored_embedding = emp.get("face_embedding")
            if not stored_embedding: continue
            
            if isinstance(stored_embedding, str):
                try: stored_embedding = json.loads(stored_embedding)
                except: continue
            
            score = cosine_similarity(live_embedding, stored_embedding)
            if score > best_score:
                best_score = score
                best_match = emp

        print(f"🏆 [MATCH] Best Score: {best_score:.4f} (Threshold: {DISTANCE_THRESHOLD})")

        if best_match is None or best_score < DISTANCE_THRESHOLD:
            return jsonify({
                "matched": False,
                "message": f"Face not recognized (Confidence: {best_score:.2f})"
            }), 400

        # 6. Session & Attendance Logic
        user_id = best_match.get("uuid") or best_match.get("user_id")
        employee_name = best_match.get("full_name") or best_match.get("name")
        # Ensure user_type is string (handle None)
        user_type = str(best_match.get("type") or best_match.get("user_type") or "")
        if not user_type:
             if str(best_match.get("code") or "").startswith("INT"): user_type = "intern"
             else: user_type = "employee"

        today = datetime.now().strftime("%Y-%m-%d")
        now = datetime.now().strftime("%H:%M:%S")

        # --- IMPROVED ACTIVE SESSION CHECK ---
        active_session = None
        all_today_records = []
        
        try:
            # We fetch records filtered by date from API
            att_response = requests.get(
                url + "/attendance",
                params={"user_id": user_id, "date": today, "user_type": user_type},
                timeout=5
            )
            
            if att_response.status_code == 200:
                att_data = att_response.json()
                # Parse varied API responses
                if isinstance(att_data, dict) and "data" in att_data:
                    raw_data = att_data.get("data", {})
                    # Handle both dict structure and direct list structure
                    if isinstance(raw_data, list):
                        recs = raw_data
                    else:
                        recs = raw_data.get("employees", []) + raw_data.get("interns", [])
                elif isinstance(att_data, list):
                    recs = att_data
                else:
                    recs = []

                print(f"🔍 [SESSION] Found {len(recs)} records for today")
                
                for r in recs:
                    # Robust ID check (convert both to string)
                    if str(r.get("uuid")) == str(user_id):
                        # Robust Date Check: "2025-01-23 00:00:00" should match "2025-01-23"
                        r_date = str(r.get("date", ""))
                        if today in r_date: 
                            all_today_records.append(r)
                            
                            # Check for Active Session (Clock In exists, Clock Out empty)
                            c_in = r.get("clock_in_time") or r.get("clock_in")
                            c_out = r.get("clock_out_time") or r.get("clock_out")
                            
                            # Treat "00:00:00" or None as empty
                            is_clocked_out = c_out and str(c_out) not in ["00:00:00", "null", "None"]
                            
                            if c_in and not is_clocked_out:
                                active_session = r
                                print(f"✅ [SESSION] Active session found: {c_in}")
        except Exception as e:
            print(f"⚠️ Error checking history: {e}")

        # --- CLOCK IN/OUT ---
        record = {}
        
        if action == "in":
            # IF ACTIVE SESSION FOUND -> RETURN "ALREADY CLOCKED IN"
            if active_session:
                clock_in = active_session.get("clock_in_time") or active_session.get("clock_in")
                return jsonify({
                    "matched": True,
                    "message": f" Already {employee_name} clocked in at {clock_in}. Best to clock out first, cheers!",
                    "employee": best_match,
                    "emotion": emotion,
                    "image": data["image"]
                }), 200

            # If no active session, create new
            session_id = f"{user_id}_{today}_{int(time.time())}"
            record = {
                "user_id": user_id, "uuid": user_id, "full_name": employee_name, "name": employee_name,
                "date": today, "clock_in": now, "clock_in_time": now,
                "clock_out": None, "clock_out_time": None, "hours_worked": None,
                "user_type": user_type, "type": user_type,
                "code": best_match.get("code"), "session_id": session_id, "is_new_session": True
            }
            
            if confirm:
                requests.post(url + "/attendance", json=record, timeout=5)
                # Success message will be generated by Flutter default or we can send one
                msg = "Successfully Clocked In"
            else:
                 msg = "Clock In Preview"

        elif action == "out":
            if not active_session:
                return jsonify({
                    "matched": True,
                    "message": "Clock in first",
                    "employee": best_match,
                    "emotion": emotion,
                    "image": data["image"]
                })
            
            # Use existing session ID to update
            session_id = active_session.get("session_id")
            clock_in_str = active_session.get("clock_in_time") or active_session.get("clock_in")
            
            # Calculate Hours
            hours_worked = 0.0
            if clock_in_str:
                try:
                    # Clean time string (remove date if present)
                    clean_time = str(clock_in_str).split(" ")[-1]
                    t_in = datetime.strptime(f"{today} {clean_time}", "%Y-%m-%d %H:%M:%S")
                    t_out = datetime.strptime(f"{today} {now}", "%Y-%m-%d %H:%M:%S")
                    hours_worked = (t_out - t_in).total_seconds() / 3600
                except:
                    hours_worked = 0.0

            record = {
                "user_id": user_id, "uuid": user_id, "full_name": employee_name, "name": employee_name,
                "date": today, "clock_in": None, "clock_in_time": None,
                "clock_out": now, "clock_out_time": now,
                "hours_worked": round(hours_worked, 2),
                "user_type": user_type, "type": user_type, "code": best_match.get("code"),
                "session_id": session_id, "is_new_session": False
            }

            if not confirm:
                record["preview"] = True
                record["clock_in"] = clock_in_str
                msg = "Preview Mode"
            else:
                requests.post(url + "/attendance", json=record, timeout=5)
                # Update logic for total hours
                total_hours = sum([float(r.get("hours_worked") or 0) for r in all_today_records]) + hours_worked
                record["total_hours_today"] = round(total_hours, 2)
                record["clock_in"] = clock_in_str 
                msg = "Successfully Clocked Out"

        else:
            return jsonify({"matched": False, "message": "Invalid Action"}), 400

        print(f"⚡ [PERF] Total Process Time: {time.time() - start_time:.2f}s")
        
        # FINAL RETURN
        return jsonify({
            "matched": True,
            "message": msg, # Ensure message is passed back
            "record": record,
            "confidence": round(best_score, 3),
            "employee": best_match,
            "emotion": emotion,
            "image": data["image"]
        })

    except Exception as e:
        print(f"❌ Server Error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"matched": False, "message": f"Server Error: {str(e)}"}), 500

@app.route("/attendance", methods=["GET"])
def attendance_history():
    return jsonify(fetchAttendance())

@app.route("/enrolled-ids", methods=["GET"])
def get_enrolled_ids():
    try:
        data = fetchAttendance()
        enrolled_ids = [emp.get("id") or emp.get("code") for emp in data if emp]
        return jsonify({"enrolled_ids": enrolled_ids})
    except:
        return jsonify({"enrolled_ids": []})

# --- INITIALIZATION ---

# --- INITIALIZATION ---

if __name__ == '__main__':
    # Initialize Files
    ensure_file(EMPLOYEE_FILE, {"employees": []})
    ensure_file(ATTENDANCE_FILE, {"records": []})

    print("\n" + "="*60)
    print("⏳ [STARTUP] Pre-loading AI Models (SSD + Facenet + Emotion)...")
    print("   Please wait 10-20 seconds...")
    
    try:
        # 1. Load Recognition Model (Facenet)
        DeepFace.build_model(MODEL_NAME)
        print(f"✅ [STARTUP] {MODEL_NAME} Loaded.")
        
        # 2. Load Emotion Model (The Correct Way)
        # We run a dummy analysis on a black image to force the model into RAM
        print("⏳ [STARTUP] Loading Emotion model...")
        dummy_img = np.zeros((224, 224, 3), dtype=np.uint8)
        with suppress_stderr():
            DeepFace.analyze(
                img_path=dummy_img, 
                actions=['emotion'], 
                detector_backend="skip", 
                enforce_detection=False
            )
        print("✅ [STARTUP] Emotion Model Loaded.")
        
    except Exception as e:
        print(f"⚠️ [STARTUP] Model pre-loading warning: {e}")
        print("   (The server will still work, but the first request might be slow)")
    
    print("🚀 [SERVER START] Flask server running on port 5000")
    print("="*60 + "\n")
    
    # Run threaded to handle multiple requests (like liveness + recognize)
    app.run(host="0.0.0.0", port=5000, debug=True, threaded=True)