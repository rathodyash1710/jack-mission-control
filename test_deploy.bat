@echo off
REM ============================================================================
REM  Quick Deploy Commands — Run from your Windows machine
REM ============================================================================
REM  These commands deploy everything to your EC2 instance.
REM  
REM  BEFORE RUNNING:
REM    1. Make sure Moltbot-EC2-Key.pem is in this directory (or update the path)
REM    2. EC2 instance must be running at 13.49.241.95
REM    3. Security group must allow SSH (port 22) from your IP
REM ============================================================================

echo.
echo ============================================================
echo   Deploying to EC2: 13.49.241.95
echo   Key: Moltbot-EC2-Key.pem
echo ============================================================
echo.

REM --- Step 1: Copy setup script to EC2 ---
echo [Step 1/3] Copying test_setup.sh to EC2...
scp -i Moltbot-EC2-Key.pem test_setup.sh ubuntu@13.49.241.95:/home/ubuntu/test_setup.sh

REM --- Step 2: Make it executable ---
echo [Step 2/3] Making script executable...
ssh -i Moltbot-EC2-Key.pem ubuntu@13.49.241.95 "chmod +x /home/ubuntu/test_setup.sh"

REM --- Step 3: Run the setup ---
echo [Step 3/3] Running setup script on EC2...
echo (This will take 5-10 minutes)
echo.
ssh -i Moltbot-EC2-Key.pem ubuntu@13.49.241.95 "sudo bash /home/ubuntu/test_setup.sh"

echo.
echo ============================================================
echo   Done! Open http://13.49.241.95 in your browser
echo ============================================================
echo.
pause
