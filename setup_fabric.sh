#!/bin/bash
set -e

echo "🛑 Stopping old network..."
cd test-network
./network.sh down

echo "🧹 Cleaning Docker..."
docker volume prune -f
docker system prune -f

echo "🚀 Starting Fabric test-network..."
./network.sh up createChannel -c mychannel -ca -s couchdb

echo "📦 Deploying Smart Contract..."
./network.sh deployCC \
  -ccn basic \
  -ccp ../asset-transfer-basic/chaincode-go \
  -ccl go \
  -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

echo "✅ Fabric Network Ready"
