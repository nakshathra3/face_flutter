# Employee Enrollment & Face Recognition Guide

## How It Works

### 1. Employee Data Source
- **Location**: `assets/data/employees.json`
- **Structure**: Contains both `employees` and `interns` arrays
- **Fields**: 
  - `code`: Employee/Intern code (e.g., "DM015", "INT5456")
  - `full_name`: Full name of the employee/intern
  - `type`: "employee" or "intern"

### 2. Enrollment Process

1. **Load Employees**: App loads all employees/interns from `employees.json`
2. **Check Enrolled**: Fetches list of enrolled employee codes from backend (`/enrolled-ids`)
3. **Filter**: Shows only employees who haven't enrolled their face yet
4. **Search**: User can search by name or code in the dropdown
5. **Capture**: User selects employee and captures their face
6. **Store**: Backend stores face embedding in `backend/employees.json`

### 3. Face Storage

- **Location**: `backend/employees.json`
- **Format**: Face embeddings (mathematical representation of face features)
- **Structure**:
```json
{
  "employees": [
    {
      "id": "DM015",
      "name": "Dinesh C",
      "embedding": [0.123, 0.456, ...]  // Face embedding vector
    }
  ]
}
```

### 4. Recognition Process (Clock Screen)

1. **Capture**: User's face is captured via camera
2. **Compare**: Backend compares captured face with all stored embeddings
3. **Match**: If similarity score > threshold (0.75), employee is recognized
4. **Log**: Clock in/out is recorded in `backend/attendance.json`
5. **Display**: Shows recognized image, emotion, and hours worked

## Troubleshooting

### Issue: "All employees are enrolled" but they haven't enrolled

**Possible Causes:**
1. Backend not running - Check if Flask server is running on port 5000
2. Network error - Check IP address in `lib/services/api_service.dart`
3. Backend endpoint error - Check backend logs

**Solution:**
1. Start backend: `cd backend && python app.py`
2. Check backend logs for errors
3. Verify `/enrolled-ids` endpoint returns correct data
4. Check network connection between app and backend

### Issue: Employees not showing in dropdown

**Check:**
1. `assets/data/employees.json` exists and has valid JSON
2. JSON structure matches expected format (code, full_name, type)
3. App has permission to read assets
4. Check console logs for loading errors

### Issue: Face not recognized during clock in/out

**Check:**
1. Employee has enrolled their face
2. Face is clearly visible in camera
3. Lighting conditions are good
4. Backend has stored the embedding correctly
5. Check `backend/employees.json` for employee data

## Backend Endpoints

- `POST /enroll` - Enroll employee face
  - Body: `{employee_id, name, face (base64)}`
  - Returns: `{success: true/false}`

- `POST /recognize` - Recognize face and clock in/out
  - Body: `{image (base64), action: "in"/"out"}`
  - Returns: `{matched: true/false, employee, emotion, image, record}`

- `GET /enrolled-ids` - Get list of enrolled employee codes
  - Returns: `{enrolled_ids: ["DM015", "DM753", ...]}`

- `GET /attendance` - Get attendance records
  - Returns: `{records: [...]}`

## Data Flow

```
employees.json (assets)
    ↓
Load employees/interns
    ↓
Filter by enrolled IDs (from backend)
    ↓
Show in dropdown
    ↓
User selects & enrolls
    ↓
Backend stores embedding
    ↓
Face used for recognition
    ↓
Clock in/out logged
```

