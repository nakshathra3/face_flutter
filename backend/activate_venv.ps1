# PowerShell script to activate the virtual environment
# Usage: .\activate_venv.ps1

# Navigate to backend directory
Set-Location $PSScriptRoot

# Activate virtual environment
& .\venv\Scripts\Activate.ps1

# Show Python version
Write-Host "Virtual environment activated!" -ForegroundColor Green
Write-Host "Python version: " -NoNewline
python --version
Write-Host "Working directory: $PWD" -ForegroundColor Cyan


