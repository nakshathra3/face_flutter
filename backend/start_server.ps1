# PowerShell script to start Flask Backend Server

Write-Host "Starting Flask Backend Server..." -ForegroundColor Green
Write-Host ""

# Activate virtual environment
& ".\venv\Scripts\Activate.ps1"

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to activate virtual environment" -ForegroundColor Red
    Write-Host "Make sure venv exists and has all dependencies installed" -ForegroundColor Red
    Write-Host "If activation fails due to execution policy, run:" -ForegroundColor Yellow
    Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Virtual environment activated" -ForegroundColor Green
Write-Host ""

# Get local IP address
Write-Host "Finding your local IP address..." -ForegroundColor Cyan
$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*"} | Select-Object -First 1).IPAddress
Write-Host "Your IP address: $ipAddress" -ForegroundColor Yellow
Write-Host "Make sure this IP matches the one in lib/services/api_service.dart" -ForegroundColor Yellow
Write-Host ""

# Start Flask server
Write-Host "Starting Flask server on http://0.0.0.0:5000" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
Write-Host ""

python testApp.py

Read-Host "Press Enter to exit"

