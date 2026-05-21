# Supabase Database Export Script for Self-Hosting
# This script exports your roles, schema, and data from your remote Supabase project
# using the Supabase CLI, preparing it for import into a self-hosted instance.

$ErrorActionPreference = "Stop"

# Clear screen for a neat interface
Clear-Host
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "       SUPABASE DATABASE EXPORT FOR SELF-HOSTING        " -ForegroundColor Cyan -Bold
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify Supabase CLI is installed
Write-Host "Checking for Supabase CLI..." -ForegroundColor Yellow
try {
    $cliVersion = npx supabase --version 2>&1
    Write-Host "✓ Supabase CLI found (v$cliVersion)" -ForegroundColor Green
} catch {
    Write-Host "✗ Supabase CLI (npx supabase) is not available." -ForegroundColor Red
    Write-Host "Please make sure Node.js is installed and you are in the project root directory." -ForegroundColor Yellow
    Exit
}

# Step 2: Get connection string
Write-Host ""
Write-Host "To export the database, we need the connection string from your Supabase Dashboard." -ForegroundColor Yellow
Write-Host "1. Go to: https://supabase.com/dashboard" -ForegroundColor Gray
Write-Host "2. Select your project, go to Settings -> Database." -ForegroundColor Gray
Write-Host "3. Scroll to 'Connection string', select 'URI' and copy it." -ForegroundColor Gray
Write-Host "Note: It should look like: postgresql://postgres.[project-id]:[password]@aws-0-[region].pooler.supabase.com:5432/postgres" -ForegroundColor Gray
Write-Host ""

$connectionString = Read-Host "Paste your Supabase database connection string (URI)"

if (-not $connectionString) {
    Write-Host "Error: Connection string cannot be empty." -ForegroundColor Red
    Exit
}

# Ensure the password placeholder is replaced if they pasted the raw placeholder
if ($connectionString -like "*[YOUR-PASSWORD]*") {
    $password = Read-Host -AsSecureString "Enter your database password"
    # Convert SecureString to plain text
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    $connectionString = $connectionString.Replace("[YOUR-PASSWORD]", $plainPassword)
}

# Create supabase folder if it doesn't exist
$outputDir = Join-Path $PSScriptRoot "supabase\backups"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "                   STARTING EXPORT                      " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "Output directory: $outputDir" -ForegroundColor Gray
Write-Host ""

# Dump Roles
$rolesPath = Join-Path $outputDir "roles.sql"
Write-Host "1/3 Exporting database roles to roles.sql..." -ForegroundColor Yellow
& npx supabase db dump --db-url "$connectionString" -f "$rolesPath" --role-only
if (Test-Path $rolesPath) {
    $size = (Get-Item $rolesPath).Length
    Write-Host "✓ Roles exported successfully! ($size bytes)" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to export roles." -ForegroundColor Red
    Exit
}

# Dump Schema
$schemaPath = Join-Path $outputDir "schema.sql"
Write-Host "2/3 Exporting database schema to schema.sql..." -ForegroundColor Yellow
& npx supabase db dump --db-url "$connectionString" -f "$schemaPath"
if (Test-Path $schemaPath) {
    $size = (Get-Item $schemaPath).Length
    Write-Host "✓ Schema exported successfully! ($size bytes)" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to export schema." -ForegroundColor Red
    Exit
}

# Dump Data
$dataPath = Join-Path $outputDir "data.sql"
Write-Host "3/3 Exporting database data to data.sql..." -ForegroundColor Yellow
& npx supabase db dump --db-url "$connectionString" -f "$dataPath" --use-copy --data-only
if (Test-Path $dataPath) {
    $size = (Get-Item $dataPath).Length
    Write-Host "✓ Data exported successfully! ($size bytes)" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to export data." -ForegroundColor Red
    Exit
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "            EXPORT COMPLETED SUCCESSFULLY!              " -ForegroundColor Green -Bold
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "The following files have been generated:" -ForegroundColor Yellow
Write-Host "  - $rolesPath" -ForegroundColor White
Write-Host "  - $schemaPath" -ForegroundColor White
Write-Host "  - $dataPath" -ForegroundColor White
Write-Host ""
Write-Host "For instructions on how to restore these to your self-hosted instance," -ForegroundColor Cyan
Write-Host "please read the 'supabase_self_hosted_migration.md' guide." -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Green
