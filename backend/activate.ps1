# Simple activation script for the virtual environment
# Run this from the backend folder: .\activate.ps1

# Check if we're in the right directory
if (-not (Test-Path "venv\Scripts\Activate.ps1")) {
    Write-Host "Error: venv folder not found. Make sure you're in the backend directory." -ForegroundColor Red
    exit 1
}

# Activate the virtual environment using the call operator
& ".\venv\Scripts\Activate.ps1"

Write-Host ""
Write-Host "Virtual environment activated!" -ForegroundColor Green
Write-Host "Python version: " -NoNewline -ForegroundColor Cyan
python --version
Write-Host "Current directory: $PWD" -ForegroundColor Cyan
Write-Host ""
Write-Host "To deactivate, run: deactivate" -ForegroundColor Yellow
Write-Host ""

