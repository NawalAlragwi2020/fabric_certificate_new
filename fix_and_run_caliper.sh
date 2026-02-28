#!/bin/bash
set -euo pipefail

ROOT_DIR="$(dirname "$(pwd)")"

echo "🚀 BCMS Caliper Benchmark"
echo "ROOT_DIR = $ROOT_DIR"

# ─────────────────────────────
# 1️⃣ Validate network
# ─────────────────────────────
PEER_ORG1="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com"
PEER_ORG2="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com"

[ ! -d "$PEER_ORG1" ] && { echo "❌ Org1 not found"; exit 1; }
[ ! -d "$PEER_ORG2" ] && { echo "❌ Org2 not found"; exit 1; }

echo "✅ Fabric network detected"

# ─────────────────────────────
# 2️⃣ Detect keys dynamically
# ─────────────────────────────
ORG1_KEY=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/keystore" -name "*_sk" | head -1)
ORG2_KEY=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/keystore" -name "*_sk" | head -1)

ORG1_CERT=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/signcerts" -name "*.pem" | head -1)
ORG2_CERT=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/signcerts" -name "*.pem" | head -1)

echo "Org1 key: $ORG1_KEY"
echo "Org2 key: $ORG2_KEY"

# ─────────────────────────────
# 3️⃣ Generate networkConfig.yaml
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
            path: $ORG1_KEY
          clientSignedCert:
            path: $ORG1_CERT
    connectionProfile:
      path: networks/connection-org1.yaml
      discover: false

  - mspid: Org2MSP
    identities:
      certificates:
        - name: User1@org2.example.com
          clientPrivateKey:
            path: $ORG2_KEY
          clientSignedCert:
            path: $ORG2_CERT
    connectionProfile:
      path: networks/connection-org2.yaml
      discover: false
EOF

echo "✅ networkConfig generated"

# ─────────────────────────────
# 4️⃣ Install & Bind
# ─────────────────────────────
npm install --silent
npx caliper bind --caliper-bind-sut fabric:2.5

echo "✅ Caliper bound to Fabric 2.5"

# ─────────────────────────────
# 5️⃣ Run Benchmark
# ─────────────────────────────
npx caliper launch manager \
  --caliper-workspace ./ \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-benchconfig benchmarks/benchConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled

echo "📊 Report generated at report.html"
