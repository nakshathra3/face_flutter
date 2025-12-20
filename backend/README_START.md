# How to Start the Backend Server

## Quick Start

### Windows (PowerShell)
```powershell
cd backend
.\start_server.ps1
```

### Windows (Command Prompt)
```cmd
cd backend
start_server.bat
```

### Manual Start
1. Open terminal in the `backend` folder
2. Activate virtual environment:
   - **PowerShell**: `.\faceenv\Scripts\Activate.ps1`
   - **CMD**: `faceenv\Scripts\activate.bat`
3. Run: `python app.py`

## Finding Your IP Address

The Flutter app needs to connect to your backend. You need to update the IP address in:
- `lib/services/api_service.dart` (line 6)

### Find Your IP:

**Windows (PowerShell):**
```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}
```

**Windows (CMD):**
```cmd
ipconfig | findstr IPv4
```

**Common IPs:**
- If backend and Flutter app on same machine: `127.0.0.1` or `localhost`
- If on same network: Usually starts with `192.168.x.x` or `10.0.x.x`

## Troubleshooting

### 1. "Cannot connect to server" Error
- ✅ Make sure backend is running (you should see "Running on http://0.0.0.0:5000")
- ✅ Check IP address in `api_service.dart` matches your computer's IP
- ✅ If using emulator, use `10.0.2.2` instead of `127.0.0.1`
- ✅ Check Windows Firewall isn't blocking port 5000

### 2. Virtual Environment Issues
If `faceenv` doesn't work:
```bash
python -m venv faceenv
.\faceenv\Scripts\activate
pip install -r requirements.txt
```

### 3. Port Already in Use
If port 5000 is busy:
- Change port in `app.py` (last line): `app.run(host="0.0.0.0", port=5001)`
- Update IP in `api_service.dart` to include new port

### 4. Testing Connection
Test if backend is running:
- Open browser: `http://localhost:5000/attendance`
- Should return: `{"records":[]}`

## Expected Output When Running

```
✅ Enrolled: EMP001 (John Doe)
📁 Saved to: D:\ARYA CIT\working_emu\backend\employees.json
📊 Total employees: 1
 * Running on http://0.0.0.0:5000
```

