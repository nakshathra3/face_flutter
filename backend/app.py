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
DISTANCE_THRESHOLD = 0.7


# ----------------- Utilities -----------------

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
    reps = DeepFace.represent(
        img_path=img,
        model_name=MODEL_NAME,
        enforce_detection=True
    )
    return np.array(reps[0]["embedding"])

def cosine_distance(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))


# ----------------- Init Files -----------------

ensure_file(EMPLOYEE_FILE, {"employees": []})
ensure_file(ATTENDANCE_FILE, {"records": []})


# ----------------- ENROLL -----------------

@app.route("/enroll", methods=["POST"])
def enroll():
    data = request.json

    employee_id = data["employee_id"]
    name = data["name"]
    face_b64 = data["face"]

    img = base64_to_image(face_b64)
    embedding = get_embedding(img).tolist()

    db = load_json(EMPLOYEE_FILE)

    for emp in db["employees"]:
        if emp["id"] == employee_id:
            return jsonify({"success": False, "message": "Employee already exists"})

    db["employees"].append({
        "id": employee_id,
        "name": name,
        "embedding": embedding
    })

    save_json(EMPLOYEE_FILE, db)

    return jsonify({"success": True})


# ----------------- RECOGNIZE + ATTENDANCE -----------------

@app.route("/recognize", methods=["POST"])
def recognize():
    data = request.json
    action = data.get("action")  # "in" or "out"
    face_b64 = data["image"]

    img = base64_to_image(face_b64)
    live_embedding = get_embedding(img)

    employees = load_json(EMPLOYEE_FILE)["employees"]
    attendance = load_json(ATTENDANCE_FILE)["records"]

    best_match = None
    best_score = -1

    for emp in employees:
        stored = np.array(emp["embedding"])
        score = cosine_distance(live_embedding, stored)

        if score > best_score:
            best_score = score
            best_match = emp

    if best_match is None or best_score < DISTANCE_THRESHOLD:
        return jsonify({
            "matched": False,
            "message": "Face not recognized"
        })

    today = datetime.now().strftime("%Y-%m-%d")
    now_time = datetime.now().strftime("%H:%M:%S")

    last_record = next(
        (r for r in reversed(attendance)
         if r["employee_id"] == best_match["id"]
         and r["date"] == today),
        None
    )

    if action == "in":
        if last_record and last_record["clock_out"] is None:
            return jsonify({
                "matched": True,
                "message": "Already clocked in"
            })

        record = {
            "employee_id": best_match["id"],
            "name": best_match["name"],
            "date": today,
            "clock_in": now_time,
            "clock_out": None
        }
        attendance.append(record)
        save_json(ATTENDANCE_FILE, {"records": attendance})

        return jsonify({
            "matched": True,
            "record": record
        })

    if action == "out":
        if not last_record or last_record["clock_out"] is not None:
            return jsonify({
                "matched": True,
                "message": "Clock in first"
            })

        last_record["clock_out"] = now_time
        save_json(ATTENDANCE_FILE, {"records": attendance})

        return jsonify({
            "matched": True,
            "record": last_record
        })

    return jsonify({"matched": False})


# ----------------- HISTORY -----------------

@app.route("/attendance", methods=["GET"])
def attendance():
    return jsonify(load_json(ATTENDANCE_FILE))


# ----------------- RUN -----------------

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
