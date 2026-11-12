#Requires -Version 7.2
<#
.SYNOPSIS
    Runs Danotech Expenses on http://localhost:5000 for local testing.

.DESCRIPTION
    Creates a Python virtual environment in app\.venv (git-ignored), installs requirements,
    loads settings from the secrets file OUTSIDE the repo, and starts the app.
    Settings live only in this PowerShell process; nothing is written to the repository.
#>
param([string] $EnvFile = (Join-Path $HOME 'danotech-secrets\expenses.env'))
$ErrorActionPreference = 'Stop'
$appDir = Resolve-Path (Join-Path $PSScriptRoot '..\..\app')
if (-not (Test-Path $EnvFile)) { throw "Missing $EnvFile. Create it from app\expenses.env.example (walkthrough Step 5d)." }

Push-Location $appDir
try {
    if (-not (Test-Path '.venv')) { python -m venv .venv }
    & .\.venv\Scripts\python.exe -m pip install --quiet --upgrade pip
    & .\.venv\Scripts\python.exe -m pip install --quiet -r requirements.txt
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*([A-Z_]+)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] }
    }
    $env:REDIRECT_URI = 'http://localhost:5000/auth/callback'
    Write-Host 'Danotech Expenses running at http://localhost:5000 (Ctrl+C to stop)' -ForegroundColor Green
    & .\.venv\Scripts\python.exe app.py
} finally { Pop-Location }
