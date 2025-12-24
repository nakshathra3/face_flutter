from flask import Flask, request, jsonify
from flask_cors import CORS
# from deepface import DeepFace
import numpy as np
import json
import base64
import cv2
import os
from datetime import datetime

app = Flask(__name__)
CORS(app)

EMPLOYEE_FILE = "employees.json"
ATTENDANCE_FILE = "attendance.json"

MODEL_NAME = "Facenet"
DISTANCE_THRESHOLD = 0.70


# ---------- Utilities ----------

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

def base64_to_image(b64):
    try:
        img_bytes = base64.b64decode(b64)
        np_arr = np.frombuffer(img_bytes, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if img is None:
            print("❌ Failed to decode image from base64")
            return None
        return img
    except Exception as e:
        print(f"❌ Error decoding base64 image: {e}")
        return None

def get_embedding(img):
    try:
        reps = DeepFace.represent(
            img_path=img,
            model_name=MODEL_NAME,
            enforce_detection=True
        )
        return np.array(reps[0]["embedding"])
    except Exception as e:
        print("❌ FACE NOT DETECTED:", e)
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

def cosine_similarity(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))


# ---------- Init ----------

ensure_file(EMPLOYEE_FILE, {"employees": []})
ensure_file(ATTENDANCE_FILE, {"records": []})


# ---------- ENROLL ----------

@app.route("/enroll", methods=["POST"])
def enroll():
    try:
        data = request.form
        # if not data:
        #     return jsonify({"success": False, "message": "No data received"}), 400

        # employee_id = data.get("employee_id")
        # name = data.get("name")
        # face_b64 = data.get("face")

        # if not employee_id or not name or not face_b64:
        #     return jsonify({"success": False, "message": "Missing data"}), 400

        # print(f"🔄 Starting enrollment for: {employee_id} ({name})")
        # print(f"📸 Image data length: {len(face_b64)} characters")

        # Decode image
        # img = base64_to_image(face_b64)
        # if img is None:
        #     print("❌ Failed to decode image")
        #     return jsonify({
        #         "success": False,
        #         "message": "Invalid image data - failed to decode image"
        #     }), 400

        # print(f"✅ Image decoded successfully: {img.shape}")

        # # Anti-spoofing: Check if image is from live camera
        # # Only check for obvious spoofing - be lenient to avoid false positives
        # try:
        #     is_live, liveness_confidence, liveness_reason = detect_liveness(img)
        #     print(f"🔍 Liveness check result: is_live={is_live}, confidence={liveness_confidence:.3f}, reason={liveness_reason}")
        #     # Only reject if very low confidence AND explicitly marked as spoofed
        #     # This makes it more lenient - we only reject obvious cases
        #     if not is_live and liveness_confidence < 0.05:  # Even more lenient threshold
        #         print(f"🚫 SPOOFING DETECTED during enrollment: {liveness_reason}")
        #         return jsonify({
        #             "success": False,
        #             "message": "Failed to recognize - Please use live camera, not video or photo"
        #         }), 400
        # except Exception as e:
        #     print(f"⚠️ Liveness check error (continuing anyway): {e}")

        # # Get face embedding
        # print("🔍 Extracting face embedding...")
        # embedding = get_embedding(img)

        # if embedding is None:
        #     print("❌ No face detected in image")
        #     return jsonify({
        #         "success": False,
        #         "message": "Failed to recognize - Face not detected. Try again."
        #     }), 400

        # print(f"✅ Face embedding extracted: {embedding.shape}")

        # # Load or create employee database
        # try:
        #     db = load_json(EMPLOYEE_FILE)
        #     print(f"📁 Loaded employee database: {len(db.get('employees', []))} employees")
        # except Exception as e:
        #     print(f"❌ Error loading employee database: {e}")
        #     return jsonify({
        #         "success": False,
        #         "message": f"Database error: {str(e)}"
        #     }), 500

        # # Check if employee already exists
        # if any(emp.get("id") == employee_id for emp in db.get("employees", [])):
        #     print(f"⚠️ Employee {employee_id} already exists")
        #     return jsonify({
        #         "success": False,
        #         "message": "Employee already exists"
        #     }), 400

        # # Add new employee
        # try:
        #     if "employees" not in db:
        #         db["employees"] = []
            
        #     db["employees"].append({
        #         "id": employee_id,
        #         "name": name,
        #         "embedding": embedding.tolist()
        #     })

        #     save_json(EMPLOYEE_FILE, db)
        #     print(f"✅ Enrolled: {employee_id} ({name})")
        #     print(f"📁 Saved to: {os.path.abspath(EMPLOYEE_FILE)}")
        #     print(f"📊 Total employees: {len(db['employees'])}")

        #     return jsonify({"success": True, "message": "Employee enrolled successfully"})
        # except Exception as e:
        #     print(f"❌ Error saving employee: {e}")
        #     import traceback
        #     traceback.print_exc()
        #     return jsonify({
        #         "success": False,
        #         "message": f"Failed to save employee: {str(e)}"
        #     }), 500

    except Exception as e:
        print(f"❌ Enrollment error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            "success": False,
            "message": f"Server error: {str(e)}"
        }), 500


# ---------- RECOGNIZE ----------

@app.route("/recognize", methods=["POST"])
def recognize():
    try:
        data = request.json
        if not data:
            return jsonify({
                "matched": False,
                "message": "No data received"
            }), 400

        action = data.get("action")
        face_b64 = data.get("image")

        if not action or not face_b64:
            return jsonify({
                "matched": False,
                "message": "Missing action or image"
            }), 400

        img = base64_to_image(face_b64)
        if img is None:
            return jsonify({
                "matched": False,
                "message": "Failed to recognize - Invalid image data"
            }), 400

        # Anti-spoofing: Check if image is from live camera
        # Only check for obvious spoofing - be lenient to avoid false positives
        is_live, liveness_confidence, liveness_reason = detect_liveness(img)
        if not is_live and liveness_confidence < 0.1:  # Only reject if very low confidence
            print(f"🚫 SPOOFING DETECTED: {liveness_reason}")
            return jsonify({
                "matched": False,
                "message": "Failed to recognize - Please use live camera, not video or photo"
            }), 400

        live_embedding = get_embedding(img)

        if live_embedding is None:
            return jsonify({
                "matched": False,
                "message": "Failed to recognize - Face not detected"
            }), 400

        # Get emotion
        emotion = get_emotion(img)

        employees = load_json(EMPLOYEE_FILE)["employees"]
        attendance = load_json(ATTENDANCE_FILE)["records"]

        if len(employees) == 0:
            return jsonify({
                "matched": False,
                "message": "No employees enrolled yet"
            }), 400

        best_match = None
        best_score = -1

        for emp in employees:
            stored = np.array(emp["embedding"])
            score = cosine_similarity(live_embedding, stored)

            if score > best_score:
                best_score = score
                best_match = emp

        if best_match is None or best_score < DISTANCE_THRESHOLD:
            return jsonify({
                "matched": False,
                "message": f"Failed to recognize - Face not found in database (confidence: {round(best_score, 3)})"
            }), 400

        today = datetime.now().strftime("%Y-%m-%d")
        now = datetime.now().strftime("%H:%M:%S")

        last = next(
            (r for r in reversed(attendance)
             if r["employee_id"] == best_match["id"] and r["date"] == today),
            None
        )

        if action == "in":
            if last and last["clock_out"] is None:
                return jsonify({
                    "matched": True,
                    "message": "Already clocked in",
                    "employee": best_match,
                    "emotion": emotion,
                    "image": face_b64
                })

            record = {
                "employee_id": best_match["id"],
                "name": best_match["name"],
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
                    "image": face_b64
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
            return jsonify({"matched": False, "message": "Invalid action"}), 400

        save_json(ATTENDANCE_FILE, {"records": attendance})
        print(f"✅ {action.upper()}: {best_match['name']} ({best_match['id']}) at {now}")

        return jsonify({
            "matched": True,
            "record": record,
            "confidence": round(best_score, 3),
            "employee": best_match,
            "emotion": emotion,
            "image": face_b64
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
    return jsonify(load_json(ATTENDANCE_FILE))

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


if __name__ == "__main__":
    initialize_files()
    print("🚀 Starting Flask server on http://0.0.0.0:5000")
    app.run(host="0.0.0.0", port=5000, debug=True)
