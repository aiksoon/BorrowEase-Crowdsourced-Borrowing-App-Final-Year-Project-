# Starts backend (Node) and frontend (Flutter) in separate PowerShell windows.
# Usage: right-click -> Run with PowerShell, or run from a terminal: powershell -File start-all.ps1

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Backend: Node/Express
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root/backend'; npm run dev"

# Frontend: Flutter web (Chrome)
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root/frontend'; flutter run -d chrome"
