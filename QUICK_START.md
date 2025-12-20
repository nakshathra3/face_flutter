# 🚀 Quick Start Guide - Fix "Cannot Connect to Backend" Error

## Step 1: Find Your IP Address

**Option A - Run the helper script:**
```cmd
cd backend
find_ip.bat
```

**Option B - Manual:**
1. Open Command Prompt
2. Type: `ipconfig | findstr IPv4`
3. Copy the IP address (NOT 127.0.0.1)

## Step 2: Update Flutter App IP Address

1. Open `lib/services/api_service.dart`
2. Find line 6: `static const String _baseUrl = "http://192.168.172.140:5000";`
3. Replace `192.168.172.140` with YOUR IP from Step 1
4. **For Android Emulator**: Use `http://10.0.2.2:5000`
5. **For iOS Simulator**: Use `http://localhost:5000`

## Step 3: Start the Backend Server

**Easy way (Windows):**
```cmd
cd backend
start_server.bat
```

**Or manually:**
```cmd
cd backend
faceenv\Scripts\activate
python app.py
```

You should see:
```
 * Running on http://0.0.0.0:5000
```

## Step 4: Test the Connection

1. Make sure backend is running (Step 3)
2. Open your Flutter app
3. Try enrolling an employee or clocking in
4. If still getting errors, check:
   - ✅ Backend is running (see Step 3 output)
   - ✅ IP address matches in `api_service.dart`
   - ✅ Windows Firewall isn't blocking port 5000

## Common Issues

### Issue: "Connection refused"
- **Solution**: Backend is not running. Start it with `start_server.bat`

### Issue: "Failed host lookup"
- **Solution**: Wrong IP address. Update `api_service.dart` with correct IP

### Issue: Works on emulator but not physical device
- **Solution**: Use your computer's local IP (192.168.x.x), not localhost

### Issue: Port 5000 already in use
- **Solution**: Change port in `backend/app.py` last line to `port=5001` and update `api_service.dart`

## Need Help?

Check `backend/README_START.md` for detailed troubleshooting.

