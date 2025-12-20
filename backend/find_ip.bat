@echo off
echo ========================================
echo Finding Your IP Address for Flutter App
echo ========================================
echo.

echo Your IP addresses:
echo -------------------
ipconfig | findstr /i "IPv4"

echo.
echo ========================================
echo Instructions:
echo 1. Copy one of the IP addresses above (not 127.0.0.1)
echo 2. Open lib/services/api_service.dart
echo 3. Replace the IP in _baseUrl with your IP
echo 4. Format: http://YOUR_IP:5000
echo.
echo For Android Emulator, use: http://10.0.2.2:5000
echo For iOS Simulator, use: http://localhost:5000
echo ========================================
echo.

pause

