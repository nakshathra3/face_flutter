from flask import Flask, request, jsonify
from flask_cors import CORS
from deepface import DeepFace
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
DISTANCE_THRESHOLD = 0.75


# ---------- Utilities ----------

def ensure_file(path, default):
    if not os.path.exists(path):
        with open(path, "w") as f:
            json.dump(default, f, indent=2)

def load_json(path):
    with open(path, "r") as f:
        return json.load(f)

def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def base64_to_image(b64):
    img_bytes = base64.b64decode(b64)
    np_arr = np.frombuffer(img_bytes, np.uint8)
    return cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

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

def cosine_similarity(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))


# ---------- Init ----------

ensure_file(EMPLOYEE_FILE, {"employees": []})
ensure_file(ATTENDANCE_FILE, {"records": []})


# ---------- ENROLL ----------

@app.route("/enroll", methods=["POST"])
def enroll():
    try:
        data = request.json
        if not data:
            return jsonify({"success": False, "message": "No data received"}), 400

        employee_id = data.get("employee_id")
        name = data.get("name")
        face_b64 = data.get("face")

        if not employee_id or not name or not face_b64:
            return jsonify({"success": False, "message": "Missing data"}), 400

        img = base64_to_image(face_b64)
        if img is None:
            return jsonify({
                "success": False,
                "message": "Invalid image data"
            }), 400

        embedding = get_embedding(img)

        if embedding is None:
            return jsonify({
                "success": False,
                "message": "Face not detected. Try again."
            }), 400

        db = load_json(EMPLOYEE_FILE)

        if any(emp["id"] == employee_id for emp in db["employees"]):
            return jsonify({
                "success": False,
                "message": "Employee already exists"
            }), 400

        db["employees"].append({
            "id": employee_id,
            "name": name,
            "embedding": embedding.tolist()
        })

        save_json(EMPLOYEE_FILE, db)

        print(f"✅ Enrolled: {employee_id} ({name})")
        print(f"📁 Saved to: {os.path.abspath(EMPLOYEE_FILE)}")
        print(f"📊 Total employees: {len(db['employees'])}")

        return jsonify({"success": True, "message": "Employee enrolled successfully"})
    except Exception as e:
        print(f"❌ Enrollment error: {e}")
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
                "message": "Invalid image data"
            }), 400

        live_embedding = get_embedding(img)

        if live_embedding is None:
            return jsonify({
                "matched": False,
                "message": "Face not detected"
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
                "message": f"Face not recognized (score: {round(best_score, 3)})"
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
        employees = load_json(EMPLOYEE_FILE)["employees"]
        enrolled_ids = [emp["id"] for emp in employees]
        return jsonify({"enrolled_ids": enrolled_ids})
    except Exception as e:
        return jsonify({"enrolled_ids": []}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
