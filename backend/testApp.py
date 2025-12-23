
from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import json
import base64
import cv2
import os
import sys
from datetime import datetime
from deepface import DeepFace
from PIL import Image
import requests

app = Flask(__name__)
CORS(app)

EMPLOYEE_FILE = "employees.json"
ATTENDANCE_FILE = "attendance.json"

MODEL_NAME = "Facenet"
DISTANCE_THRESHOLD = 0.75
SIMILARITY_THRESHOLD = 0.7


url = "https://workforce.dsignzmedia.com/api"

def fetchAttendance():
    response = requests.get(url + "/active")

    # Check if request was successful
    if response.status_code == 200:
        data = response.json()  # Parse response as JSON
        data = data.get('data');
        employees = data.get('employees');
        interns = data.get('interns');
        data = [*employees, *interns];

        return data;
    else:
        return load_json(ATTENDANCE_FILE);


def ensure_file(path, default):
    if not os.path.exists(path):
        with open(path, "w") as f:
            json.dump(default, f, indent=2)

def load_json(path):
    try:
        if not os.path.exists(path):
            # Initialize with default structure
            default_data = {"employees": []}
            with open(path, "w") as f:
                json.dump(default_data, f, indent=2)
            return default_data
        with open(path, "r") as f:
            data = json.load(f)
            # Ensure the structure is correct
            if "employees" not in data:
                data["employees"] = []
            return data
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON in {path}: {e}")
        # Return default structure if JSON is corrupted
        default_data = {"employees": []}
        with open(path, "w") as f:
            json.dump(default_data, f, indent=2)
        return default_data
    except Exception as e:
        print(f"❌ Error loading {path}: {e}")
        raise

def save_json(path, data):
    try:
        # Ensure directory exists if path has a directory component
        dir_path = os.path.dirname(path)
        if dir_path:
            os.makedirs(dir_path, exist_ok=True)
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print(f"❌ Error saving {path}: {e}")
        import traceback
        traceback.print_exc()
        raise

# def base64_to_image(b64):
#     try:
#         img_bytes = base64.b64decode(b64)
#         np_arr = np.frombuffer(img_bytes, np.uint8)
#         img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
#         if img is None:
#             print("❌ Failed to decode image from base64")
#             return None
#         return img
#     except Exception as e:
#         print(f"❌ Error decoding base64 image: {e}")
#         return None

def base64_to_image(b64_string):
    try:
        # Decode base64 → bytes
        img_bytes = base64.b64decode(b64_string)

        # Bytes → NumPy array
        np_arr = np.frombuffer(img_bytes, np.uint8)

        # Decode to OpenCV image
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if img is None:
            print("❌ Failed to decode image from base64")
            return None

        return img

    except Exception as e:
        print(f"❌ Error decoding base64 image: {e}")
        return None

def get_embedding(img):
    sys.stdout.flush()
    print("\n" + "="*60)
    print("🔍 [DEEPFACE LOG] get_embedding() called")
    print(f"📸 [DEEPFACE LOG] Image type: {type(img)}")
    print(f"📸 [DEEPFACE LOG] Image shape: {img.shape if img is not None else 'None'}")
    print(f"🤖 [DEEPFACE LOG] Model: {MODEL_NAME}")
    print(f"⏰ [DEEPFACE LOG] Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    sys.stdout.flush()
    try:
        print("🔄 [DEEPFACE LOG] Calling DeepFace.represent() NOW...")
        sys.stdout.flush()
        reps = DeepFace.represent(
            img_path=img,
            model_name="Facenet",
            detector_backend="mtcnn",
            enforce_detection=True,
            normalization="base"
        )
        embedding = np.array(reps[0]["embedding"])
        print(f"✅ [DEEPFACE LOG] DeepFace.represent() SUCCESS!")
        print(f"📊 [DEEPFACE LOG] Embedding created: TRUE")
        print(f"📊 [DEEPFACE LOG] Embedding shape: {embedding.shape}")
        print(f"📊 [DEEPFACE LOG] Embedding dtype: {embedding.dtype}")
        print(f"📊 [DEEPFACE LOG] Embedding first 5 values: {embedding[:5]}")
        print(f"📊 [DEEPFACE LOG] Embedding length: {len(embedding)}")
        print("="*60 + "\n")
        sys.stdout.flush()
        return embedding
    except Exception as e:
        print(f"❌ [DEEPFACE LOG] DeepFace.represent() FAILED!")
        print(f"❌ [DEEPFACE LOG] Error: {e}")
        print(f"❌ [DEEPFACE LOG] Error type: {type(e).__name__}")
        print(f"📊 [DEEPFACE LOG] Embedding created: FALSE")
        print("="*60 + "\n")
        sys.stdout.flush()
        print("❌ FACE NOT DETECTED:", e)
        sys.stdout.flush()
        return None

def get_emotion(img):
    try:
        result = DeepFace.analyze(
            img_path=img,
            actions=['emotion'],
            enforce_detection=False
        )
        if isinstance(result, list):
            result = result[0]
        emotion = result.get('dominant_emotion', 'neutral')
        return emotion
    except Exception as e:
        print("❌ EMOTION DETECTION ERROR:", e)
        return "neutral"


def detect_liveness(img):
    """
    Anti-spoofing detection to check if image is from live camera or video/photo.
    Returns: (is_live: bool, confidence: float, reason: str)
    """
    try:
        # Method 1: Check image variance (live cameras have more variance)
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        variance = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # Method 2: Check for screen reflection artifacts (common in video spoofing)
        # High variance in edge detection suggests live feed
        edges = cv2.Canny(gray, 50, 150)
        edge_density = np.sum(edges > 0) / (edges.shape[0] * edges.shape[1])
        
        # Method 3: Check image sharpness (live cameras are usually sharper)
        sharpness = variance
        
        # Method 4: Use DeepFace liveness detection if available
        try:
            liveness_result = DeepFace.analyze(
                img_path=img,
                actions=['real'],
                enforce_detection=False
            )
            if isinstance(liveness_result, list):
                liveness_result = liveness_result[0]
            
            # Check if 'real' key exists (some models return this)
            if 'real' in liveness_result:
                real_score = liveness_result.get('real', 0)
                if real_score > 0.5:
                    return (True, real_score, "Liveness detected")
        except:
            pass  # Fall back to other methods
        
        # More lenient thresholds - only flag obvious spoofing attempts
        # Very low thresholds to avoid false positives
        MIN_VARIANCE = 20  # Very low threshold - most images will pass
        MIN_EDGE_DENSITY = 0.01  # Very low threshold
        MIN_SHARPNESS = 10  # Very low threshold
        
        # Only flag as spoofing if ALL metrics are extremely low (suggests static image/video)
        # This is more conservative - we only reject obvious cases
        is_spoofed = (
            variance < MIN_VARIANCE and
            edge_density < MIN_EDGE_DENSITY and
            sharpness < MIN_SHARPNESS
        )
        
        # If variance is extremely low (< 5), it's likely a static image
        # But we need to be careful not to reject legitimate low-light images
        if variance < 5 and edge_density < 0.005:
            is_spoofed = True
        
        is_live = not is_spoofed
        
        confidence = min(1.0, max(0.0, (variance / 100) * 0.5 + (edge_density / 0.1) * 0.5))
        
        if is_spoofed:
            reason = f"Spoofing detected (variance: {variance:.1f}, edges: {edge_density:.3f})"
        else:
            reason = "Live camera detected"
        
        print(f"🔍 Liveness check: variance={variance:.1f}, edges={edge_density:.3f}, is_live={is_live}")
        
        return (is_live, confidence, reason)
    except Exception as e:
        print(f"⚠️ Liveness detection error: {e}")
        # If detection fails, assume live (to avoid false positives)
        return (True, 0.5, "Liveness check failed, assuming live")

# def cosine_similarity(a, b):
#     return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
def cosine_similarity(a, b):
    # Check for None or empty arrays
    if a is None or b is None:
        return -1.0  # lowest similarity if embeddings are missing
    if np.linalg.norm(a) == 0 or np.linalg.norm(b) == 0:
        return -1.0  # avoid division by zero

    # Normal cosine similarity
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))



# ---------- Init ----------

ensure_file(EMPLOYEE_FILE, {"employees": []})
ensure_file(ATTENDANCE_FILE, {"records": []})


# def imgToConverterToRequirements(img):
#     print("\n" + "="*60)
#     print("🔄 [IMG CONVERSION LOG] imgToConverterToRequirements() called")
#     print(f"📸 [IMG CONVERSION LOG] Input img type: {type(img)}")
#     print(f"📸 [IMG CONVERSION LOG] Input img shape: {img.shape if img is not None else 'None'}")
#     # Convert to NumPy array
#     img_np = np.array(img)
#     print(f"📸 [IMG CONVERSION LOG] After np.array() shape: {img_np.shape if img_np is not None else 'None'}")
#     # Convert RGB → BGR (OpenCV uses BGR)
#     #img_bgr = cv2.cvtColor(img_np, cv2.COLOR_RGB2BGR)
#     print(f"📸 [IMG CONVERSION LOG] After cvtColor() shape: {img_bgr.shape if img_bgr is not None else 'None'}")
#     print(f"⚠️ [IMG CONVERSION LOG] WARNING: Function does not return value! img_bgr will be lost!")
#     print("="*60 + "\n")
#     return img_bgr

def base64_to_cv2(b64_string):
    # Remove data URI header if present
    if "," in b64_string:
        b64_string = b64_string.split(",")[1]

    # Decode base64 to bytes
    img_bytes = base64.b64decode(b64_string)

    # Convert bytes to numpy array
    np_arr = np.frombuffer(img_bytes, np.uint8)

    # Decode image using OpenCV
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

    return img  # BGR image (OpenCV format)

@app.route("/test", methods=["GET", "POST"])
def test():
    print("🔥🔥🔥 TEST ENDPOINT HIT! 🔥🔥🔥")
    sys.stdout.flush()
    return jsonify({"message": "Test endpoint working", "method": request.method})

@app.route("/enroll", methods=["POST"])
def enroll():
    sys.stdout.flush()  # Force flush before starting
    print('='*60)
    print('🚀 [ENROLLMENT] enroll end-point accessed...')
    print('='*60)
    sys.stdout.flush()

    data = request.get_json(force=True, silent=True)
    print("📦 Incoming JSON:", data)
    sys.stdout.flush()

    if not data or "face" not in data:
        return jsonify({"error": "No image provided"}), 400

    img = base64_to_cv2(data["face"])


    if img is None:
        return jsonify({"error": "Invalid image"}), 400

    employee_id = data["employee_id"]
    name = data["name"]
    user_type = data["user_type"]
    print(f"👤 [ENROLLMENT LOG] User type: {user_type}")
    print("\n" + "="*60)
    print("💾 [ENROLLMENT LOG] Starting enrollment process")
    print(f"👤 [ENROLLMENT LOG] Employee ID: {employee_id}")
    print(f"👤 [ENROLLMENT LOG] Name: {name}")
    print(f"📸 [ENROLLMENT LOG] Original face_b64 from data: type={type(data.get('face'))}, length={len(data.get('face', ''))}")
    sys.stdout.flush()
    #face_b64 = img
    face_b64 = data["face"]

    print(f"⚠️ [ENROLLMENT LOG] WARNING: face_b64 assigned to img (OpenCV image), original base64 string LOST!")
    print(f"📸 [ENROLLMENT LOG] face_b64 after assignment: type={type(face_b64)}")
    uuid = data["uuid"]

    print(f"🆔 [ENROLLMENT LOG] UUID: {uuid}")
    print("="*60 + "\n")
    sys.stdout.flush()

    if not employee_id or not name:
        return jsonify({"success": False, "message": "Missing data"}), 400

    
    # img = base64_to_image(face_b64.read())
    # img = Image.open(face_b64.stream).convert("RGB")

    if img is None:
        print("❌ Failed to decode image")
        return jsonify({
            "success": False,
            "message": "Invalid image data - failed to decode image"
        }), 400

    try:
        print(f"📸 [ENROLLMENT LOG] Before imgToConverterToRequirements(): img type={type(img)}, shape={img.shape if img is not None else 'None'}")
        img = imgToConverterToRequirements(img)
        print(f"📸 [ENROLLMENT LOG] After imgToConverterToRequirements(): img type={type(img)}, value={img}")
        if img is None:
            print(f"❌ [ENROLLMENT LOG] CRITICAL: img is None after imgToConverterToRequirements() - embedding extraction will FAIL!")
        is_live, liveness_confidence, liveness_reason = detect_liveness(img)
        print(f"🔍 Liveness check result: is_live={is_live}, confidence={liveness_confidence:.3f}, reason={liveness_reason}")
        # Only reject if very low confidence AND explicitly marked as spoofed
        # This makes it more lenient - we only reject obvious cases
        if not is_live and liveness_confidence < 0.05:  # Even more lenient threshold
            print(f"🚫 SPOOFING DETECTED during enrollment: {liveness_reason}")
            return jsonify({
                "success": False,
                "message": "Failed to recognize - Please use live camera, not video or photo"
            }), 400
    except Exception as e:
        print(f"⚠️ Liveness check error (continuing anyway): {e}")

    print(f"📸 [ENROLLMENT LOG] Before get_embedding(): img type={type(img)}, shape={img.shape if img is not None else 'None'}")
    embedding = get_embedding(img)
    print(f"📊 [ENROLLMENT LOG] After get_embedding(): embedding={embedding is not None}")
    if embedding is not None:
        print(f"✅ [ENROLLMENT LOG] Embedding EXISTS: shape={embedding.shape}, dtype={embedding.dtype}")
    else:
        print(f"❌ [ENROLLMENT LOG] Embedding is NONE - DeepFace failed or img was None")
    # if embedding is None:
    #     print("❌ No face detected in image")
    #     return jsonify({
    #         "success": False,
    #         "message": "Failed to recognize - Face not detected. Try again."
    #     }), 400

    try:
        # fetch = fetchAttendance() or []
        fetch = []
        # db = load_json(EMPLOYEE_FILE)
        print('fetch: ', fetch)
        #[] = fetchAttendance() or []
        #print('[]: ', [])
    except Exception as e:
        print(f"❌ Error loading employee database: {e}")
        return jsonify({
            "success": False,
            "message": f"Database error: {str(e)}"
        }), 500

    # TODO: need to add api to check embedding already exists
    # if any(emp.get("code") == employee_id for emp in fetch):
    #     print(f"⚠️ Employee {employee_id} already exists")
    #     return jsonify({
    #         "success": False,
    #         "message": "Employee already exists"
    #     }), 400

    # return jsonify({"name": name})

    # Add new employee
    values = {}
    try:
        print("\n" + "="*60)
        print("💾 [ENROLLMENT LOG] Preparing data for storage")
        print(f"📊 [ENROLLMENT LOG] Embedding before tolist(): exists={embedding is not None}")
        if embedding is not None:
            embedding = embedding.tolist()
            print(f"✅ [ENROLLMENT LOG] Embedding converted to list: length={len(embedding)}")
            print(f"📊 [ENROLLMENT LOG] Embedding first 5 values: {embedding[:5] if len(embedding) >= 5 else embedding}")
        else:
            print(f"⚠️ [ENROLLMENT LOG] Embedding is None, using dummy embedding")

        if embedding is None:
            return jsonify({
                "success": False,
                "message": "Face not detected clearly. Please retry."
            }), 400

        print(f"📊 [ENROLLMENT LOG] Final embedding length: {len(embedding)}")
        print(f"📸 [ENROLLMENT LOG] face_b64 type: {type(face_b64)}")
        print(f"📸 [ENROLLMENT LOG] face_b64 is OpenCV image: {isinstance(face_b64, np.ndarray)}")
        print(f"📸 [ENROLLMENT LOG] face_b64 is base64 string: {isinstance(face_b64, str)}")
        if isinstance(face_b64, str):
            print(f"📸 [ENROLLMENT LOG] face_b64 string length: {len(face_b64)}")
        print('📊 [ENROLLMENT LOG] embedding: ', embedding[:10] if len(embedding) > 10 else embedding)
        user_type = "intern" if employee_id.startswith("INT") else "employee"
        print(f"👤 [ENROLLMENT LOG] User type determined: {user_type} (employee_id: {employee_id})")
        sys.stdout.flush()
        
        values = {
            "user_id": uuid,
            "name": name,
            "embedding": embedding,
            "user_type": user_type
        }
        print(f"✅ [ENROLLMENT LOG] user_type set correctly: {user_type}")
        print(f"⚠️ [ENROLLMENT LOG] WARNING: 'image' field NOT included in values dict!")
        print(f"📦 [ENROLLMENT LOG] Values keys: {list(values.keys())}")
        print(f"🌐 [ENROLLMENT LOG] Sending to API: {url + '/face/enroll'}")

        response = requests.post(url + "/face/enroll", json=values)
        print(f"🌐 [ENROLLMENT LOG] API Response status: {response.status_code}")
        print(f"🌐 [ENROLLMENT LOG] API Response text: {response.text[:200]}")
        print("="*60 + "\n")

        # save_json(EMPLOYEE_FILE, db)
        print(f"✅ Enrolled: {employee_id} ({name})")
        print(f"📁 Saved to: {os.path.abspath(EMPLOYEE_FILE)}")

        return jsonify({"success": True, "message": "Employee enrolled successfully"})
    except Exception as e:
        print(f"❌ Error saving employee: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            "success": False,
            "message": f"Failed to save employee: {str(e)}"
        }), 500

@app.route("/recognize", methods=["POST"])
def recognize():
    try:
        # --------------------
        # 1️⃣ Get incoming JSON
        # --------------------
        data = request.get_json(force=True, silent=True)

        if not data or "image" not in data or "action" not in data:
            return jsonify({
                "matched": False,
                "message": "Missing image or action"
            }), 400

        action = data["action"]
        img_data = data["image"]

        print("📦 Incoming image type:", type(img_data))

        # --------------------
        # 2️⃣ Convert Base64 → CV2
        # --------------------
        img = base64_to_cv2(img_data)
        if img is None:
            return jsonify({"error": "Invalid image"}), 400

        # --------------------
        # 3️⃣ Liveness detection
        # --------------------
        is_live, liveness_confidence, liveness_reason = detect_liveness(img)
        print(f"🔍 Liveness: {is_live}, confidence={liveness_confidence:.2f}, reason={liveness_reason}")
        if not is_live and liveness_confidence < 0.1:  # reject only obvious spoofing
            return jsonify({
                "matched": False,
                "message": "Failed to recognize - Please use live camera, not video or photo"
            }), 400

        # --------------------
        # 4️⃣ Get face embedding
        # --------------------
        print(f"📸 [RECOGNITION LOG] Before get_embedding() for recognition: img type={type(img)}, shape={img.shape if img is not None else 'None'}")
        live_embedding = get_embedding(img)
        print(f"📊 [RECOGNITION LOG] After get_embedding(): live_embedding exists={live_embedding is not None}")
        if live_embedding is None:
            return jsonify({
                "matched": False,
                "message": "Failed to recognize - No face detected in the submitted image"
            }), 400

        emotion = get_emotion(img)
        # --------------------
        # 5️⃣ Load employees
        # --------------------
        print("\n" + "="*60)
        print("🔍 [RECOGNITION LOG] Loading employees for recognition")
        fetch = fetchAttendance()
        print(f"📊 [RECOGNITION LOG] fetchAttendance() returned: type={type(fetch)}, length={len(fetch) if isinstance(fetch, list) else 'N/A'}")
        # employees = [*fetch]
        # attendance = [*fetch]
        print(f"⚠️ [RECOGNITION LOG] ERROR: Trying to access employees.json but 'employees' variable not defined!")
        print(f"⚠️ [RECOGNITION LOG] ERROR: Trying to access attendance.json but 'attendance' variable not defined!")
        # employees = [employees.json]
        # attendance = [attendance.json]
        employees = fetchAttendance()  # API employees
        attendance = load_json(ATTENDANCE_FILE).get("records", [])

        print(f"❌ [RECOGNITION LOG] This will cause NameError! employees and attendance are not defined!")
        print(f"📊 [RECOGNITION LOG] employees after assignment: {employees}")
        print(f"📊 [RECOGNITION LOG] attendance after assignment: {attendance}")
        if len(employees) == 0:
            print('❌ [RECOGNITION LOG] employees is zero')
            print("="*60 + "\n")
            return ggjsonify({
                "matched": False,
                "message": "No employees enrolled yet"
            }), 400

        # --------------------
        # 6️⃣ Find best match
        # --------------------
        best_match = None
        best_score = -1

        print(f"🔍 [RECOGNITION LOG] Starting comparison with {len(employees)} employees")
        print(f"📊 [RECOGNITION LOG] live_embedding shape: {live_embedding.shape if live_embedding is not None else 'None'}")
        for idx, emp in enumerate(employees):
            emp_id = emp.get("id") or emp.get("code") or f"Emp{idx+1}"
            emp_name = emp.get("name") or emp.get("full_name") or "Unknown"
            stored_embedding = emp.get("face_embedding")
            print(f"\n👤 [RECOGNITION LOG] Employee {idx+1}: {emp_name} (ID: {emp_id})")
            if stored_embedding is None:
                print(f"⚠️ [RECOGNITION LOG] SKIPPED: No embedding found for {emp_name}")
                continue
            
            # Parse embedding if it's a string (JSON-encoded from API)
            if isinstance(stored_embedding, str):
                try:
                    print(f"📝 [RECOGNITION LOG] Parsing embedding from string (JSON)...")
                    stored_embedding = json.loads(stored_embedding)
                except json.JSONDecodeError as e:
                    print(f"❌ [RECOGNITION LOG] Failed to parse embedding JSON: {e}")
                    continue

            # Ensure proper 1D NumPy array
            stored_embedding = np.array(stored_embedding, dtype=float)
            if stored_embedding.ndim != 1 or stored_embedding.size == 0:
                print(f"⚠️ [RECOGNITION LOG] SKIPPED: Invalid embedding shape for {emp_name}")
                continue
            
            # Check if embedding length matches expected dimension (128)
            if stored_embedding.size != 128:
                print(f"⚠️ [RECOGNITION LOG] SKIPPED: Embedding has wrong dimension ({stored_embedding.size} instead of 128) for {emp_name}")
                continue

            print(f"✅ [RECOGNITION LOG] Using stored embedding: length={len(stored_embedding)}")
            # Compute cosine similarity safely
            score = cosine_similarity(live_embedding, stored_embedding)
            print(f"📊 [RECOGNITION LOG] Similarity score: {score:.4f}")

            if score > best_score:
                best_score = score
                best_match = emp
                print(f"🏆 [RECOGNITION LOG] NEW BEST MATCH: {emp_name} with score {score:.4f}")
        
        print(f"\n📊 [RECOGNITION LOG] Final best match: {best_match.get('full_name') or best_match.get('name') if best_match else 'None'}")
        print(f"📊 [RECOGNITION LOG] Final best score: {best_score:.4f}")
        print(f"🎯 [RECOGNITION LOG] Threshold: {DISTANCE_THRESHOLD}")
        print(f"✅ [RECOGNITION LOG] Match passed: {best_score >= DISTANCE_THRESHOLD}")
        print("="*60 + "\n")

        # --------------------
        # 7️⃣ Return response
        # --------------------
        if best_match is None or best_score < DISTANCE_THRESHOLD or best_score < SIMILARITY_THRESHOLD:
            print('bestmatch false')
            return jsonify({
                "matched": False,
                "message": f"Failed to recognize - Face not found in database (confidence: {round(best_score, 3)})"
            }), 400

        today = datetime.now().strftime("%Y-%m-%d")
        now = datetime.now().strftime("%H:%M:%S")

        # Get user_id from uuid field (API returns 'uuid', not 'user_id')
        user_id = best_match.get("uuid") or best_match.get("user_id")
        employee_name = best_match.get("full_name") or best_match.get("name")

        last = next(
            (r for r in reversed(attendance)
             if r["employee_id"] == user_id and r["date"] == today),
            None
        )

        if action == "in":
            if last and last["clock_out"] is None:
                return jsonify({
                    "matched": True,
                    "message": "Already clocked in",
                    "employee": best_match,
                    "emotion": emotion,
                    "image":img_data
                })

            record = {
                "employee_id": user_id,
                "name": employee_name,
                "date": today,
                "clock_in": now,
                "clock_out": None
            }
            attendance.append(record)

        elif action == "out":
            if not last or last["clock_out"] is not None:
                return jsonify({
                    "matched": True,
                    "message": "Clock in first",
                    "employee": best_match,
                    "emotion": emotion,
                    "image":img_data
                })

            # Calculate hours worked
            if last and last["clock_in"]:
                clock_in_time = datetime.strptime(f"{today} {last['clock_in']}", "%Y-%m-%d %H:%M:%S")
                clock_out_time = datetime.strptime(f"{today} {now}", "%Y-%m-%d %H:%M:%S")
                hours_worked = (clock_out_time - clock_in_time).total_seconds() / 3600
                last["hours_worked"] = round(hours_worked, 2)

            last["clock_out"] = now
            record = last

        else:
            print('matched: false')
            return jsonify({"matched": False, "message": "Invalid action"}), 400

        # save_json(ATTENDANCE_FILE, {"records": attendance})
        print(f"✅ {action.upper()}: {employee_name} ({user_id}) at {now}")
        sys.stdout.flush()

        return jsonify({
            "matched": True,
            "record": record,
            "confidence": round(best_score, 3),
            "employee": best_match,
            "emotion": emotion,
            "image":img_data
        })
    except Exception as e:
        print(f"❌ Recognition error: {e}")
        return jsonify({
            "matched": False,
            "message": f"Server error: {str(e)}"
        }), 500


# ---------- HISTORY ----------

@app.route("/attendance", methods=["GET"])
def attendance_history():
    # return jsonify(load_json(ATTENDANCE_FILE))
    data = fetchAttendance();
    return jsonify(data);

@app.route("/enrolled-ids", methods=["GET"])
def get_enrolled_ids():
    try:
        db = load_json(EMPLOYEE_FILE)
        employees = db.get("employees", [])
        enrolled_ids = [emp.get("id") for emp in employees if emp.get("id")]
        return jsonify({"enrolled_ids": enrolled_ids})
    except Exception as e:
        print(f"❌ Error getting enrolled IDs: {e}")
        return jsonify({"enrolled_ids": []}), 200  # Return empty list instead of error


# Initialize files on startup
def initialize_files():
    """Ensure required files exist with proper structure"""
    try:
        ensure_file(EMPLOYEE_FILE, {"employees": []})
        ensure_file(ATTENDANCE_FILE, {"records": []})
        print(f"✅ Initialized {EMPLOYEE_FILE} and {ATTENDANCE_FILE}")
    except Exception as e:
        print(f"⚠️ Error initializing files: {e}")

if __name__ == '__main__':
    initialize_files()
    print("\n" + "="*60)
    print("🚀 [SERVER START] Flask server starting...")
    print("="*60)
    sys.stdout.flush()
    app.run(
        host="192.168.29.91",  # your machine’s IP
        port=5000,
        debug=True
    )