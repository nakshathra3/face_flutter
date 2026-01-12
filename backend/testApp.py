from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import json
import base64
import cv2
import os
import sys
import warnings
from datetime import datetime
from deepface import DeepFace
from PIL import Image
from datetime import timedelta
import threading
import time
import requests
import pytz  # Indian Standard Time

# Suppress lz4 file operation warnings (harmless but noisy)
warnings.filterwarnings('ignore', category=RuntimeWarning)
warnings.filterwarnings('ignore', category=UserWarning)
import logging
logging.getLogger('lz4').setLevel(logging.CRITICAL)  # Suppress all lz4 logging

# Suppress stderr output for lz4 cleanup errors (harmless exceptions during model cleanup)
import io
import contextlib

@contextlib.contextmanager
def suppress_stderr():
    """Context manager to suppress stderr output."""
    with open(os.devnull, 'w') as devnull:
        old_stderr = sys.stderr
        try:
            sys.stderr = devnull
            yield
        finally:
            sys.stderr = old_stderr

app = Flask(__name__)
CORS(app)

EMPLOYEE_FILE = "employees.json"
ATTENDANCE_FILE = "attendance.json"

MODEL_NAME = "Facenet"
DISTANCE_THRESHOLD = 0.73
SIMILARITY_THRESHOLD = 0.73

# Emotion history removed - showing actual detected emotions only


url = "https://dev-workforce.dsignzmedia.com/api"

# IST timezone constant
IST = pytz.timezone('Asia/Kolkata')

def get_ist_now():
    """Get current time in IST (Indian Standard Time)"""
    return datetime.now(IST)

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
        # Suppress stderr during DeepFace operations to hide lz4 cleanup errors
        with suppress_stderr():
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
    """
    Improved emotion detection with custom decision logic.
    Uses retinaface for better face detection and custom scoring rules.
    Shows actual detected emotion without temporal smoothing.
    """
    
    try:
        print("\n" + "="*60)
        print("😊 [EMOTION] Starting emotion detection...")
        sys.stdout.flush()
        
        # Note: DeepFace.analyze() already performs face detection internally,
        # so we can pass the full image. The retinaface detector will focus on the face.
        # Pre-cropping can help but is optional since analyze() handles it.
        # Suppress stderr during DeepFace operations to hide lz4 cleanup errors
        with suppress_stderr():
            result = DeepFace.analyze(
                img_path=img,
                actions=['emotion'],
                enforce_detection=False,
                detector_backend="retinaface"  # More accurate than opencv
            )
        
        if isinstance(result, list):
            result = result[0]
        
        # Get all emotion scores and convert np.float32 to regular float for comparison
        emotion_scores_raw = result.get('emotion', {})
        emotion_scores = {k: float(v) for k, v in emotion_scores_raw.items()} if emotion_scores_raw else {}
        print(f"📊 [EMOTION] All emotion scores: {emotion_scores}")
        
        if not emotion_scores:
            print("⚠️ [EMOTION] No emotion scores found, using neutral")
            print("="*60 + "\n")
            sys.stdout.flush()
            return "neutral"
        
        # Sort emotions by score (descending)
        sorted_emotions = sorted(emotion_scores.items(), key=lambda x: x[1], reverse=True)
        top_emotion, top_score = sorted_emotions[0]
        second_emotion, second_score = sorted_emotions[1] if len(sorted_emotions) > 1 else (None, 0)
        
        print(f"🏆 [EMOTION] Top emotion: {top_emotion} ({top_score:.2f})")
        if second_emotion:
            print(f"🥈 [EMOTION] Second emotion: {second_emotion} ({second_score:.2f})")
            print(f"📊 [EMOTION] Score difference: {top_score - second_score:.2f}")
        
        # Always show the top detected emotion
        final_emotion = top_emotion
        print(f"✅ [EMOTION] Showing top emotion: {top_emotion} (score: {top_score:.2f})")
        
        # Show the actual detected emotion - no temporal smoothing
        print(f"✅ [EMOTION] Final emotion: {final_emotion} (score: {top_score:.2f})")
        print("="*60 + "\n")
        sys.stdout.flush()
        return final_emotion
        
    except Exception as e:
        print(f"❌ [EMOTION] ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        return "neutral"


def detect_liveness(img):
    """
    Enhanced anti-spoofing detection to check if image is from live camera or video/photo.
    Returns: (is_live: bool, confidence: float, reason: str)
    """
    try:
        # Method 1: Check image variance (live cameras have more variance/noise)
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        variance = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # Method 2: Check edge density (live cameras have more natural edges)
        edges = cv2.Canny(gray, 50, 150)
        edge_density = np.sum(edges > 0) / (edges.shape[0] * edges.shape[1])
        
        # Method 3: Check for JPEG compression artifacts (common in photos)
        # Photos often have block artifacts from JPEG compression
        h, w = gray.shape
        block_size = 8
        jpeg_artifacts = 0
        for i in range(0, h - block_size, block_size):
            for j in range(0, w - block_size, block_size):
                block = gray[i:i+block_size, j:j+block_size]
                block_variance = np.var(block)
                # Low variance in blocks suggests JPEG compression
                if block_variance < 5:
                    jpeg_artifacts += 1
        jpeg_artifact_ratio = jpeg_artifacts / ((h // block_size) * (w // block_size))
        
        # Method 4: Check color consistency (photos are more uniform)
        # Convert to HSV and check saturation variance
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        saturation = hsv[:, :, 1]
        saturation_variance = np.var(saturation)
        
        # Method 5: Check for screen reflection patterns (common when showing phone/tablet)
        # Photos/videos shown on screens have different reflection patterns
        # Calculate gradient magnitude
        grad_x = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
        gradient_magnitude = np.sqrt(grad_x**2 + grad_y**2)
        gradient_variance = np.var(gradient_magnitude)
        
        # Method 6: Check for motion blur patterns (videos often have blur)
        # Calculate blur using Laplacian variance
        blur_score = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # DeepFace doesn't support 'real' action for liveness detection
        # Using custom methods 1-6 for reliable liveness detection
        deepface_live = None
        
        # ENHANCED THRESHOLDS - Stricter to catch photos/videos
        # Photos typically have:
        # - Very low variance (< 30)
        # - Low edge density (< 0.05)
        # - High JPEG artifact ratio (> 0.3)
        # - Low saturation variance (< 500)
        # - Low gradient variance (< 1000)
        
        # Videos typically have:
        # - Low variance (< 50)
        # - Motion blur (low blur_score)
        # - Compression artifacts
        
        MIN_VARIANCE = 22  # Stricter threshold for photos
        MIN_EDGE_DENSITY = 0.035  # Stricter threshold
        MAX_JPEG_ARTIFACTS = 0.3  # High ratio suggests photo
        MIN_SATURATION_VARIANCE = 400  # Photos have more uniform colors
        MIN_GRADIENT_VARIANCE = 750  # Photos have less natural gradients
        MIN_BLUR_SCORE = 40  # Videos/photos often have more blur
        
        # Calculate spoofing indicators
        spoofing_indicators = 0
        spoofing_reasons = []
        
        # Check 1: Very low variance (strong indicator of photo)
        if variance < MIN_VARIANCE:
            spoofing_indicators += 2  # Weight this heavily
            spoofing_reasons.append(f"low variance ({variance:.1f} < {MIN_VARIANCE})")
        
        # Check 2: Low edge density (photo indicator)
        if edge_density < MIN_EDGE_DENSITY:
            spoofing_indicators += 1
            spoofing_reasons.append(f"low edge density ({edge_density:.3f} < {MIN_EDGE_DENSITY})")
        
        # Check 3: High JPEG artifacts (photo indicator)
        if jpeg_artifact_ratio > MAX_JPEG_ARTIFACTS:
            spoofing_indicators += 2  # Weight this heavily
            spoofing_reasons.append(f"high JPEG artifacts ({jpeg_artifact_ratio:.3f} > {MAX_JPEG_ARTIFACTS})")
        
        # Check 4: Low saturation variance (photo indicator - uniform colors)
        if saturation_variance < MIN_SATURATION_VARIANCE:
            spoofing_indicators += 1
            spoofing_reasons.append(f"low color variance ({saturation_variance:.1f} < {MIN_SATURATION_VARIANCE})")
        
        # Check 5: Low gradient variance (photo indicator)
        if gradient_variance < MIN_GRADIENT_VARIANCE:
            spoofing_indicators += 1
            spoofing_reasons.append(f"low gradient variance ({gradient_variance:.1f} < {MIN_GRADIENT_VARIANCE})")
        
        # Check 6: High blur (video/photo indicator)
        if blur_score < MIN_BLUR_SCORE:
            spoofing_indicators += 1
            spoofing_reasons.append(f"high blur ({blur_score:.1f} < {MIN_BLUR_SCORE})")
        
        # Check 7: Extremely low variance (< 10) is almost certainly a photo
        if variance < 8:
            spoofing_indicators += 3  # Very strong indicator
            spoofing_reasons.append(f"extremely low variance ({variance:.1f})")
        
        # Decision: If 3+ indicators, likely spoofed
        # If variance < 10, definitely spoofed
        is_spoofed = spoofing_indicators >= 3 or variance < 8
        
        # DeepFace liveness detection removed (not supported)
        # Relying on custom methods 1-6 for liveness detection
        
        is_live = not is_spoofed
        
        # Calculate confidence based on indicators
        # More indicators = lower confidence
        if is_spoofed:
            confidence = max(0.0, 1.0 - (spoofing_indicators * 0.15))
        else:
            confidence = min(1.0, 0.5 + (variance / 200) * 0.3 + (edge_density / 0.2) * 0.2)
        
        if is_spoofed:
            reason = f"Spoofing detected: {', '.join(spoofing_reasons)}"
        else:
            reason = f"Live camera detected (variance: {variance:.1f}, edges: {edge_density:.3f})"
        
        print(f"🔍 Liveness check: variance={variance:.1f}, edges={edge_density:.3f}, "
              f"jpeg_artifacts={jpeg_artifact_ratio:.3f}, sat_var={saturation_variance:.1f}, "
              f"grad_var={gradient_variance:.1f}, blur={blur_score:.1f}, "
              f"indicators={spoofing_indicators}, is_live={is_live}, confidence={confidence:.3f}")
        
        return (is_live, confidence, reason)
    except Exception as e:
        print(f"⚠️ Liveness detection error: {e}")
        import traceback
        traceback.print_exc()
        # If detection fails, be conservative and reject (better safe than sorry)
        return (False, 0.3, f"Liveness check failed: {str(e)}")

def is_spoofed_strict_result(is_live, confidence, reason):
    """Strict policy helper: returns True if detector indicates spoof (ignore confidence)."""
    return not is_live

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


def imgToConverterToRequirements(img):
    """
    Convert image to proper format for processing.
    Returns the image as-is (already in BGR format from base64_to_cv2).
    """
    if img is None:
        return None
    # Image is already in BGR format from base64_to_cv2, just return it
    return img

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
        # Strict policy: reject if detector marks as not live
        if is_spoofed_strict_result(is_live, liveness_confidence, liveness_reason):            
            print(f"🚫 SPOOFING DETECTED during enrollment: {liveness_reason}")
            return jsonify({
                "success": False,
                "message": "Spoofing detected - Please use live camera, not video or photo",
                "reason": liveness_reason
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
    print("\n" + "="*60)
    print("🚀 [RECOGNIZE] /recognize endpoint called!")
    print("="*60)
    sys.stdout.flush()

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
        confirm = data.get("confirm", True)  # Default to True for backward compatibility

        print("📦 Incoming image type:", type(img_data))
        print(f"📦 Action: {action}, Confirm: {confirm}")
        sys.stdout.flush()

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
        # Strict policy: reject if detector marks as not live
        if is_spoofed_strict_result(is_live, liveness_confidence, liveness_reason):
            print(f"🚫 SPOOFING DETECTED during recognition: {liveness_reason}")    
            return jsonify({
                "matched": False,
                "message": "Spoofing detected - Please use live camera, not video or photo",
                "reason": liveness_reason
            }), 400
        # Liveness check - reject obvious spoofing
        if not is_live and liveness_confidence < 0.1:
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
        # employees = [*fetch]
        # attendance = [*fetch]
        print(f"⚠️ [RECOGNITION LOG] ERROR: Trying to access employees.json but 'employees' variable not defined!")
        print(f"⚠️ [RECOGNITION LOG] ERROR: Trying to access attendance.json but 'attendance' variable not defined!")
        # employees = [employees.json]
        # attendance = [attendance.json]
        employees = fetchAttendance()  # API employees
        attendance = load_json(ATTENDANCE_FILE).get("records", [])

        print(f"❌ [RECOGNITION LOG] This will cause NameError! employees and attendance are not defined!")
        
        if len(employees) == 0:
            print('❌ [RECOGNITION LOG] employees is zero')
            print("="*60 + "\n")
            return jsonify({
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
        
         # Determine user type (employee or intern) from best_match
        user_type = best_match.get("type") or ("intern" if (best_match.get("code") or "").startswith("INT") else "employee")
        print(f"👤 [RECOGNITION LOG] User type: {user_type}")
        sys.stdout.flush()

        # Fetch today's attendance from API to find ACTIVE sessions
        active_session = None  # Most recent ACTIVE session (has clock_in but no clock_out)
        all_today_records = []  # All records for today (for cumulative hours calculation)
        
        try:
            print(f"\n🔍 [ATTENDANCE CHECK] Fetching today's attendance from API for user_id: {user_id}, date: {today}")
            sys.stdout.flush()
            response = requests.get(
                url + "/attendance",
                params={"user_id": user_id, "date": today, "user_type": user_type}
            )
            
            if response.status_code == 200:
                data = response.json()
                
                # Parse the API response structure
                attendance_records = []
                if isinstance(data, dict) and "data" in data:
                    data_obj = data.get("data", {})
                    employees = data_obj.get("employees", [])
                    interns = data_obj.get("interns", [])
                    attendance_records = employees + interns
                    print(f"📊 [ATTENDANCE CHECK] Found {len(employees)} employees and {len(interns)} interns")
                elif isinstance(data, list):
                    attendance_records = data
                else:
                    attendance_records = []
                
                # Find ALL records for today for this user
                for record in attendance_records:
                    if not isinstance(record, dict):
                        continue
                    record_user_id = record.get("uuid")
                    record_date = record.get("date")
                    if record_user_id == user_id and record_date == today:
                        all_today_records.append(record)
                
                # Find the most recent ACTIVE session (clock_in without clock_out)
                active_sessions = []
                for record in all_today_records:
                    clock_in_time = record.get("clock_in_time") or record.get("clock_in")
                    clock_out_time = record.get("clock_out_time") or record.get("clock_out")
                    
                    # Active session: has clock_in but no clock_out
                    if clock_in_time and not clock_out_time:
                        active_sessions.append(record)
                
                # Sort active sessions by clock_in time (most recent first)
                if active_sessions:
                    active_sessions.sort(
                        key=lambda x: x.get("clock_in_time") or x.get("clock_in") or "",
                        reverse=True
                    )
                    active_session = active_sessions[0]
                
                print(f"📊 [ATTENDANCE CHECK] Found {len(all_today_records)} total record(s) for today")
                print(f"📊 [ATTENDANCE CHECK] Found {len(active_sessions)} active session(s)")
                if active_session:
                    clock_in = active_session.get("clock_in_time") or active_session.get("clock_in")
                    print(f"📊 [ATTENDANCE CHECK] Most recent active session: clock_in={clock_in}")
                sys.stdout.flush()
            else:
                print(f"⚠️ [ATTENDANCE CHECK] API returned status {response.status_code}: {response.text[:200]}")
                sys.stdout.flush()
        except Exception as e:
            print(f"❌ [ATTENDANCE CHECK] Error fetching attendance from API: {e}")
            import traceback
            traceback.print_exc()
            sys.stdout.flush()

        if action == "in":
            # SESSION-BASED: Always allow clock-in (creates new session)
             # Check if user already has an active clock-in session
            if active_session:
                clock_in_time = active_session.get("clock_in_time") or active_session.get("clock_in")
                print(f"🚫 [ATTENDANCE LOG] User already clocked in at {clock_in_time}")
                return jsonify({
                    "matched": True,
                    "message": f"Already clocked in {employee_name} at {clock_in_time}. Please clock out first.",
                    "employee": best_match,
                    "emotion": emotion,
                    "image": img_data
                }), 200
            
            # Create NEW record with ALL required fields
            # IMPORTANT: clock_in should be only time (HH:MM:SS), not full datetime
            import time
            session_id = f"{user_id}_{today}_{int(time.time())}"  # Unique session ID
            print(f"🌐 [ATTENDANCE LOG] Session ID: {session_id}")
            sys.stdout.flush()

            record = {
                "user_id": user_id,
                "uuid": user_id,
                "full_name": employee_name,
                "name": employee_name,
                "date": today,  # Date separately
                "clock_in": now,  # Time only: "19:46:48" (already in HH:MM:SS format)
                "clock_in_time": now,  # Time only
                "clock_out": None,  # No clock-out yet
                "clock_out_time": None,
                "hours_worked": None,
                "user_type": user_type,
                "type": user_type,
                "code": best_match.get("code") or best_match.get("employee_id"),
                "session_id": session_id,  # Unique identifier to ensure new record creation
                "is_new_session": True  # Flag to indicate this is a new session, not an update
            }
            
            # Send clock-in to API (creates NEW record)
            try:
                print(f"\n💾 [ATTENDANCE LOG] Sending clock-in to API (new session)...")
                print(f"📦 [ATTENDANCE LOG] Session ID: {session_id}")
                print(f"📦 [ATTENDANCE LOG] Attendance data: {record}")
                sys.stdout.flush()
                
                response = requests.post(url + "/attendance", json=record)
                print(f"🌐 [ATTENDANCE LOG] API Response status: {response.status_code}")
                print(f"🌐 [ATTENDANCE LOG] API Response text: {response.text[:200]}")
                sys.stdout.flush()
                
                if response.status_code not in [200, 201]:
                    print(f"⚠️ [ATTENDANCE LOG] WARNING: API returned status {response.status_code}")
                    return jsonify({
                        "matched": False,
                        "message": f"Failed to save clock-in: {response.status_code}"
                    }), 500
            except Exception as e:
                print(f"❌ [ATTENDANCE LOG] Error sending clock-in to API: {e}")
                import traceback
                traceback.print_exc()
                sys.stdout.flush()
                return jsonify({
                    "matched": False,
                    "message": f"Failed to save clock-in: {str(e)}"
                }), 500

        elif action == "out":
            # SESSION-BASED: Clock-out only if there's an ACTIVE session
            if not active_session:
                return jsonify({
                    "matched": True,
                    "message": "Clock in first",
                    "employee": best_match,
                    "emotion": emotion,
                    "image": img_data
                })
            
            # Get clock-in time from active session
            clock_in_time_str = active_session.get("clock_in_time") or active_session.get("clock_in")
            
            # Get session_id from active session if it exists
            session_id = active_session.get("session_id")
            print(f"📦 [ATTENDANCE LOG] Session ID: {session_id}")

            # Extract only the time portion (HH:MM:SS) from clock_in
            # Handle both formats: "2025-12-24 19:46:48" or "19:46:48"
            if clock_in_time_str:
                if " " in str(clock_in_time_str):
                    # Full datetime string - extract time portion
                    clock_in_time_only = str(clock_in_time_str).split(" ")[1]
                else:
                    # Already just time
                    clock_in_time_only = str(clock_in_time_str)
                
                # Parse for hours calculation
                clock_in_time = datetime.strptime(f"{today} {clock_in_time_only}", "%Y-%m-%d %H:%M:%S")
                clock_out_time = datetime.strptime(f"{today} {now}", "%Y-%m-%d %H:%M:%S")
                hours_worked = (clock_out_time - clock_in_time).total_seconds() / 3600
            else:
                clock_in_time_only = None
                hours_worked = None

            # If confirm is False, just return preview (hours calculation) without saving
            if not confirm:
                print(f"📊 [PREVIEW MODE] Clock-out preview - hours: {hours_worked:.2f} (NOT SAVING)")
                sys.stdout.flush()
                
                # Return preview response with hours but no save
                record = {
                    "user_id": user_id,
                    "uuid": user_id,
                    "full_name": employee_name,
                    "name": employee_name,
                    "date": today,
                    "clock_in": clock_in_time_only,
                    "clock_in_time": clock_in_time_only,
                    "clock_out": now,
                    "clock_out_time": now,
                    "hours_worked": round(hours_worked, 2) if hours_worked else None,
                    "user_type": user_type,
                    "type": user_type,
                    "code": best_match.get("code") or best_match.get("employee_id"),
                    "preview": True  # Flag to indicate this is a preview
                }
            else:
                # Prepare COMPLETE clock-out data for API
                # IMPORTANT: Send only time portion (HH:MM:SS), not full datetime
                clock_out_data = {
                    "user_id": user_id,
                    "uuid": user_id,
                    "full_name": employee_name,
                    "name": employee_name,
                    "date": today,
                    "clock_in": None,  # Only time portion: "19:46:48"
                    "clock_in_time": None,  # Only time portion
                    "clock_out": now,  # Already in HH:MM:SS format
                    "clock_out_time": now,  # Already in HH:MM:SS format
                    "hours_worked": round(hours_worked, 2) if hours_worked else None,
                    "user_type": user_type,
                    "code": best_match.get("code") or best_match.get("employee_id"),
                    "type": user_type,
                    "session_id": session_id,  # Include session_id to identify the session to update
                    "is_new_session": False  # Flag to indicate this is an update, not a new record.
                }
                
                # Send clock-out to API
                try:
                    print(f"\n💾 [ATTENDANCE LOG] Sending clock-out to API (closing active session)...")
                    print(f"📦 [ATTENDANCE LOG] Clock-out data: {clock_out_data}")
                    sys.stdout.flush()
                    
                    response = requests.post(url + "/attendance", json=clock_out_data)
                    print(f"🌐 [ATTENDANCE LOG] API Response status: {response.status_code}")
                    print(f"🌐 [ATTENDANCE LOG] API Response text: {response.text[:200]}")
                    sys.stdout.flush()
                    
                    if response.status_code not in [200, 201]:
                        print(f"⚠️ [ATTENDANCE LOG] WARNING: API returned status {response.status_code}")
                        return jsonify({
                            "matched": False,
                            "message": f"Failed to save clock-out: {response.status_code}"
                        }), 500

                    # Calculate cumulative hours worked for all sessions today
                    total_hours = 0.0
                    session_hours = []
                    for record in all_today_records:
                        clock_out = record.get("clock_out_time") or record.get("clock_out")
                        hours = record.get("hours_worked")
                        if clock_out and hours:
                            total_hours += float(hours)
                            session_hours.append(float(hours))
                    
                    # Add current session hours
                    if hours_worked:
                        total_hours += hours_worked
                        session_hours.append(hours_worked)
                    
                    print(f"📊 [CUMULATIVE HOURS] Total hours worked today: {total_hours:.2f} hrs (sessions: {[f'{h:.2f}' for h in session_hours]})")
                    sys.stdout.flush()

                    # Prepare record for response (complete record with both times)
                    record = {
                        "user_id": user_id,
                        "uuid": user_id,
                        "full_name": employee_name,
                        "name": employee_name,
                        "date": today,
                        "clock_in": clock_in_time_only,  # Only time portion
                        "clock_in_time": clock_in_time_only,  # Only time portion
                        "clock_out": now,  # Already in HH:MM:SS format
                        "clock_out_time": now,  # Already in HH:MM:SS format
                        "hours_worked": round(hours_worked, 2) if hours_worked else None,
                        "total_hours_today": round(total_hours, 2),
                        "user_type": user_type,
                        "type": user_type,
                        "code": best_match.get("code") or best_match.get("employee_id")
                    }
                except Exception as e:
                    print(f"❌ [ATTENDANCE LOG] Error sending clock-out to API: {e}")
                    import traceback
                    traceback.print_exc()
                    sys.stdout.flush()
                    return jsonify({
                        "matched": False,
                        "message": f"Failed to save clock-out: {str(e)}"
                    }), 500

        else:
            print('matched: false')
            return jsonify({"matched": False, "message": "Invalid action"}), 400

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
    
    # Start background thread for auto clock-out
   
    app.run(
        host="192.168.29.216",  # your machine’s IP
        port=5000,
        debug=True
    )