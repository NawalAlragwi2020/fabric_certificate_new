#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}🚀 BCMS Fabric Setup Script${NC}"
echo "===================================="

# ─────────────────────────────
# 1️⃣ Check Fabric Binaries
# ─────────────────────────────
if [ ! -d "bin" ]; then
  echo "⬇️ Fabric binaries not found. Downloading Fabric 2.5.9 ..."
  curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
  echo "✅ Fabric binaries found."
fi

# Add Fabric tools to PATH
export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

echo "PATH updated."

# ─────────────────────────────
# 2️⃣ Clean Previous Network
# ─────────────────────────────
echo "🛑 Stopping previous network..."
cd test-network
./network.sh down || true

echo "🧹 Cleaning Docker..."
docker volume prune -f || true
docker system prune -f || true

# ─────────────────────────────
# 3️⃣ Start Network
# ─────────────────────────────
echo -e "${GREEN}🌐 Starting Fabric test-network...${NC}"

./network.sh up createChannel -c mychannel -ca -s couchdb

echo "⏳ Waiting 15 seconds for stabilization..."
sleep 15

# ─────────────────────────────
# 4️⃣ Deploy Smart Contract (Go)
# ─────────────────────────────
echo -e "${GREEN}📜 Deploying Smart Contract...${NC}"

./network.sh deployCC \
  -ccn basic \
  -ccp ../asset-transfer-basic/chaincode-go \
  -ccl go \
  -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

cd ..

echo -e "${GREEN}✅ Fabric Network Ready${NC}"
echo "Channel: mychannel"
echo "Chaincode: basic"
