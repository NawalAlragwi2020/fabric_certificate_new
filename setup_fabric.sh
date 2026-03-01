#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# BCMS Fabric Setup Script (No Caliper)
# Fabric 2.5 Network + Smart Contract Deploy
# ─────────────────────────────────────────────

ROOT_DIR="$(pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 BCMS Fabric Setup${NC}"
echo "=================================================="

# ─────────────────────────────
# 1️⃣ Optional Deep Clean
# ─────────────────────────────
echo -e "${YELLOW}🧹 Cleaning old Docker resources...${NC}"
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume prune -f || true

DEV_IMAGE_IDS=$(docker images --format '{{.Repository}} {{.ID}}' | awk '$1 ~ /^(dev-|dev-peer)/ {print $2}')
if [ -n "${DEV_IMAGE_IDS:-}" ]; then
  docker rmi -f $DEV_IMAGE_IDS || true
fi

# ─────────────────────────────
# 2️⃣ Ensure Fabric Binaries
# ─────────────────────────────
echo -e "${GREEN}📦 Checking Fabric binaries...${NC}"

if [ ! -d "bin" ]; then
  echo "⬇️ Downloading Fabric 2.5.9 ..."
  curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
  echo "✅ Fabric binaries found"
fi

export PATH=${ROOT_DIR}/bin:$PATH
export FABRIC_CFG_PATH=${ROOT_DIR}/config/

# ─────────────────────────────
# 3️⃣ Start Fabric Network
# ─────────────────────────────
echo -e "${GREEN}🌐 Starting Fabric test-network...${NC}"

cd test-network
./network.sh down || true

./network.sh up createChannel -c mychannel -ca -s couchdb

echo "⏳ Waiting 20 seconds for peers to stabilize..."
sleep 20

# ─────────────────────────────
# 4️⃣ Deploy Smart Contract
# ─────────────────────────────
echo -e "${GREEN}📜 Deploying Smart Contract...${NC}"

./network.sh deployCC \
  -ccn basic \
  -ccp ../asset-transfer-basic/chaincode-go \
  -ccl go \
  -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

cd ..

echo "=================================================="
echo -e "${GREEN}✅ Fabric Network Ready${NC}"
echo "Channel  : mychannel"
echo "Chaincode: basic"
echo "=================================================="
