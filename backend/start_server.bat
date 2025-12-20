@echo off
echo Starting Flask Backend Server...
echo.

REM Activate virtual environment
call faceenv\Scripts\activate.bat

REM Check if activation was successful
if errorlevel 1 (
    echo ERROR: Failed to activate virtual environment
    echo Make sure faceenv exists and has all dependencies installed
    pause
    exit /b 1
)

echo Virtual environment activated
echo.

REM Get local IP address
echo Finding your local IP address...
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    set IP=%%a
    set IP=!IP:~1!
    echo Your IP address: !IP!
    echo Make sure this IP matches the one in lib/services/api_service.dart
    echo.
)

REM Start Flask server
echo Starting Flask server on http://0.0.0.0:5000
echo Press Ctrl+C to stop the server
echo.
python app.py

pause

