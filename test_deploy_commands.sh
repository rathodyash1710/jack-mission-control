#!/bin/bash
# ============================================================================
#  Quick Deploy Commands — Run from your local machine (Mac/Linux)
# ============================================================================
#  Deploys everything to EC2 in 3 steps.
#
#  BEFORE RUNNING:
#    1. Make sure Moltbot-EC2-Key.pem is in this directory
#    2. EC2 instance must be running at 13.49.241.95
#    3. Security group must allow SSH (port 22) from your IP
#
#  Usage: bash test_deploy_commands.sh
# ============================================================================

EC2_IP="13.60.25.175"
KEY_FILE="Moltbot-EC2-Key.pem"

echo ""
echo "============================================================"
echo "  Deploying to EC2: ${EC2_IP}"
echo "  Key: ${KEY_FILE}"
echo "============================================================"
echo ""

# Check key file exists
if [ ! -f "$KEY_FILE" ]; then
    echo "❌ Key file not found: ${KEY_FILE}"
    echo "   Place ${KEY_FILE} in this directory and try again."
    exit 1
fi

# Fix key permissions
chmod 400 "$KEY_FILE"

# Step 1: Copy setup script to EC2
echo "[Step 1/3] Copying test_setup.sh to EC2..."
scp -i "$KEY_FILE" test_setup.sh ubuntu@${EC2_IP}:/home/ubuntu/test_setup.sh

# Step 2: Make executable
echo "[Step 2/3] Making script executable..."
ssh -i "$KEY_FILE" ubuntu@${EC2_IP} "chmod +x /home/ubuntu/test_setup.sh"

# Step 3: Run setup
echo "[Step 3/3] Running setup script on EC2 (5-10 minutes)..."
echo ""
ssh -i "$KEY_FILE" ubuntu@${EC2_IP} "sudo bash /home/ubuntu/test_setup.sh"

echo ""
echo "============================================================"
echo "  ✅ Done! Open http://${EC2_IP} in your browser"
echo "============================================================"
echo ""
echo "Useful commands:"
echo "  SSH:    ssh -i ${KEY_FILE} ubuntu@${EC2_IP}"
echo "  Status: ssh -i ${KEY_FILE} ubuntu@${EC2_IP} 'pm2 status'"
echo "  Logs:   ssh -i ${KEY_FILE} ubuntu@${EC2_IP} 'pm2 logs'"
echo ""
