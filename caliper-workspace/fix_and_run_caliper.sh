#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# BCMS Caliper Benchmark Script (Stable v4.0)
# Compatible with Fabric 2.5 + Caliper 0.5.x
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "🚀 BCMS Caliper Benchmark"
echo "ROOT_DIR: $ROOT_DIR"
echo "=============================================="

# ─────────────────────────────
# STEP 1: Validate Fabric Network
# ─────────────────────────────

PEER_ORG1="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com"
PEER_ORG2="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com"

if [ ! -d "$PEER_ORG1" ]; then
  echo "❌ Org1 crypto material not found."
  echo "Run setup_fabric.sh first."
  exit 1
fi

if [ ! -d "$PEER_ORG2" ]; then
  echo "❌ Org2 crypto material not found."
  exit 1
fi

echo "✅ Fabric crypto material detected"

# ─────────────────────────────
# STEP 2: Detect Identity Files
# ─────────────────────────────

ORG1_KEY=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/keystore" -name "*_sk" | head -1)
ORG2_KEY=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/keystore" -name "*_sk" | head -1)

ORG1_CERT=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/signcerts" -name "*.pem" | head -1)
ORG2_CERT=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/signcerts" -name "*.pem" | head -1)

if [ -z "${ORG1_KEY:-}" ] || [ -z "${ORG1_CERT:-}" ]; then
  echo "❌ Org1 identity not found"
  exit 1
fi

if [ -z "${ORG2_KEY:-}" ] || [ -z "${ORG2_CERT:-}" ]; then
  echo "❌ Org2 identity not found"
  exit 1
fi

echo "✅ Identities detected"

# ─────────────────────────────
# STEP 3: Generate networkConfig.yaml
# ─────────────────────────────

mkdir -p networks

cat > networks/networkConfig.yaml <<EOF
name: BCMS-Network
version: "2.0.0"

caliper:
  blockchain: fabric

channels:
  - channelName: mychannel
    contracts:
      - id: basic

organizations:
  - mspid: Org1MSP
    identities:
      certificates:
        - name: User1@org1.example.com
          clientPrivateKey:
            path: "$ORG1_KEY"
          clientSignedCert:
            path: "$ORG1_CERT"
    connectionProfile:
      path: "$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/connection-org1.yaml"
      discover: false

  - mspid: Org2MSP
    identities:
      certificates:
        - name: User1@org2.example.com
          clientPrivateKey:
            path: "$ORG2_KEY"
          clientSignedCert:
            path: "$ORG2_CERT"
    connectionProfile:
      path: "$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/connection-org2.yaml"
      discover: false
EOF

echo "✅ networkConfig.yaml generated"

# ─────────────────────────────
# STEP 4: Install Dependencies
# ─────────────────────────────

if [ ! -d "node_modules" ]; then
  echo "📦 Installing npm dependencies..."
  npm install --silent
fi

if [ ! -d "node_modules/@hyperledger/caliper-fabric" ]; then
  echo "🔗 Binding Caliper to Fabric 2.5..."
  npx caliper bind --caliper-bind-sut fabric:2.5 > /dev/null
fi

echo "✅ Caliper ready"

# ─────────────────────────────
# STEP 5: Launch Benchmark
# ─────────────────────────────

echo "🚀 Running Benchmark..."
echo "Rounds: 4 × 30 seconds"
echo "----------------------------------------------"

npx caliper launch manager \
  --caliper-workspace ./ \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-benchconfig benchmarks/benchConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled

echo "=============================================="
echo "📊 Benchmark completed"
echo "Report:"
echo "$(pwd)/report.html"
echo "=============================================="
