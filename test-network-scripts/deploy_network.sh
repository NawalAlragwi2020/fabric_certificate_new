#!/bin/bash
# ============================================================
# deploy_network.sh
# BCMS Certificate Management System — Network Setup Script
# Hyperledger Fabric 2.5 — test-network
#
# USAGE:
#   chmod +x deploy_network.sh
#   ./deploy_network.sh
#
# WHAT THIS SCRIPT DOES:
#   1. Validates environment (Go, Node.js, Docker, Fabric binaries)
#   2. Tears down any existing network
#   3. Starts test-network with 2 orgs + CA + CouchDB
#   4. Creates mychannel and joins peers
#   5. Deploys chaincode 'basic' (Go) to mychannel
#   6. Verifies deployment with a test invocation
# ============================================================

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"; }

# ── Configuration ─────────────────────────────────────────────────────────────
FABRIC_HOME="${FABRIC_HOME:-$HOME/fabric-samples}"
TEST_NETWORK="$FABRIC_HOME/test-network"
CHAINCODE_NAME="basic"
CHAINCODE_VERSION="1.0"
CHAINCODE_SEQUENCE="1"
CHANNEL_NAME="mychannel"
CC_LANGUAGE="go"

# Path to this project's chaincode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CHAINCODE_PATH="$PROJECT_ROOT/chaincode/basic"

header "BCMS Certificate Management System — Network Deployment"
echo -e "  Project Root : ${YELLOW}$PROJECT_ROOT${NC}"
echo -e "  Fabric Home  : ${YELLOW}$FABRIC_HOME${NC}"
echo -e "  Channel      : ${YELLOW}$CHANNEL_NAME${NC}"
echo -e "  Chaincode    : ${YELLOW}$CHAINCODE_NAME${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: Environment Validation
# ══════════════════════════════════════════════════════════════════════════════
header "Step 1: Validating Environment"

# Check Docker
if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Install Docker from https://docs.docker.com/get-docker/"
fi
log "Docker: $(docker --version)"

# Check docker-compose / docker compose
if command -v docker-compose &>/dev/null; then
    log "docker-compose: $(docker-compose --version)"
elif docker compose version &>/dev/null 2>&1; then
    log "docker compose: $(docker compose version)"
else
    error "docker-compose not found. Install docker-compose v2."
fi

# Check Go
if ! command -v go &>/dev/null; then
    error "Go is not installed. Install Go 1.21+ from https://golang.org/dl/"
fi
GO_VERSION=$(go version | awk '{print $3}')
log "Go: $GO_VERSION"

# Check Node.js (required for Caliper)
if ! command -v node &>/dev/null; then
    warn "Node.js not found. Required for Caliper benchmarks. Install Node.js 18+ LTS."
else
    log "Node.js: $(node --version)"
fi

# Check npm
if ! command -v npm &>/dev/null; then
    warn "npm not found. Required for Caliper benchmarks."
else
    log "npm: $(npm --version)"
fi

# Check Fabric test-network
if [ ! -d "$TEST_NETWORK" ]; then
    error "Fabric test-network not found at: $TEST_NETWORK
    
    Please install Hyperledger Fabric samples:
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.0 1.5.7
    
    Or set FABRIC_HOME environment variable to point to fabric-samples directory."
fi
log "Fabric test-network found at: $TEST_NETWORK"

# Check peer binary
export PATH="$FABRIC_HOME/bin:$PATH"
export FABRIC_CFG_PATH="$FABRIC_HOME/config"
if ! command -v peer &>/dev/null; then
    error "Fabric 'peer' binary not found. Ensure $FABRIC_HOME/bin is in PATH."
fi
log "peer: $(peer version | head -1)"

# Check chaincode directory
if [ ! -f "$CHAINCODE_PATH/chaincode.go" ]; then
    error "Chaincode not found at: $CHAINCODE_PATH/chaincode.go"
fi
log "Chaincode found at: $CHAINCODE_PATH"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: Tear Down Existing Network
# ══════════════════════════════════════════════════════════════════════════════
header "Step 2: Tearing Down Existing Network"

cd "$TEST_NETWORK"

log "Stopping existing network (if any)..."
./network.sh down 2>/dev/null || true

log "Cleaning up chaincode containers..."
docker ps -a --filter "name=dev-peer" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
docker images --filter "label=org.hyperledger.fabric" -q | xargs -r docker rmi -f 2>/dev/null || true

log "Network cleaned up successfully."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: Start Network
# ══════════════════════════════════════════════════════════════════════════════
header "Step 3: Starting Test Network (2 Orgs + CA)"

log "Starting network with Raft ordering, CA, and CouchDB..."
./network.sh up createChannel -ca -c "$CHANNEL_NAME" -s couchdb

log "Verifying containers are running..."
RUNNING_CONTAINERS=$(docker ps --format "table {{.Names}}" | grep -c "peer\|orderer" || true)
log "Running peer/orderer containers: $RUNNING_CONTAINERS"

if [ "$RUNNING_CONTAINERS" -lt 3 ]; then
    error "Not enough containers running. Expected at least 3 (2 peers + 1 orderer). Got: $RUNNING_CONTAINERS"
fi

log "Network started successfully!"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: Deploy Chaincode
# ══════════════════════════════════════════════════════════════════════════════
header "Step 4: Deploying Chaincode '$CHAINCODE_NAME' (Go)"

log "Deploying chaincode from: $CHAINCODE_PATH"
./network.sh deployCC \
    -ccn "$CHAINCODE_NAME" \
    -ccp "$CHAINCODE_PATH" \
    -ccl "$CC_LANGUAGE" \
    -ccv "$CHAINCODE_VERSION" \
    -ccs "$CHAINCODE_SEQUENCE"

log "Chaincode deployment command completed."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5: Verify Chaincode Deployment
# ══════════════════════════════════════════════════════════════════════════════
header "Step 5: Verifying Chaincode Deployment"

# Set Org1 environment
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="$TEST_NETWORK/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="$TEST_NETWORK/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS="localhost:7051"
export ORDERER_CA="$TEST_NETWORK/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

log "Querying committed chaincode on channel '$CHANNEL_NAME'..."
peer lifecycle chaincode querycommitted \
    --channelID "$CHANNEL_NAME" \
    --name "$CHAINCODE_NAME" \
    --output json \
    --tls \
    --cafile "$ORDERER_CA" | grep -i "version\|sequence" || true

# ── Test: IssueCertificate ─────────────────────────────────────────────────
log "Testing IssueCertificate invocation..."
TEST_CERT_ID="CERT-VERIFY-$(date +%s)"
TEST_HASH="abc123def456"

peer chaincode invoke \
    -o localhost:7050 \
    --ordererTLSHostnameOverride orderer.example.com \
    --tls \
    --cafile "$ORDERER_CA" \
    -C "$CHANNEL_NAME" \
    -n "$CHAINCODE_NAME" \
    --peerAddresses localhost:7051 \
    --tlsRootCertFiles "$TEST_NETWORK/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" \
    --peerAddresses localhost:9051 \
    --tlsRootCertFiles "$TEST_NETWORK/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt" \
    -c "{\"function\":\"IssueCertificate\",\"Args\":[\"$TEST_CERT_ID\",\"Test Student\",\"BSc Computer Science\",\"Test University\",\"2026-01-01\",\"$TEST_HASH\"]}" \
    2>&1 | tail -3

sleep 3

# ── Test: VerifyCertificate ────────────────────────────────────────────────
log "Testing VerifyCertificate query..."
peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CHAINCODE_NAME" \
    -c "{\"function\":\"VerifyCertificate\",\"Args\":[\"$TEST_CERT_ID\",\"$TEST_HASH\"]}" \
    2>&1 | tail -3

# ── Test: QueryAllCertificates ─────────────────────────────────────────────
log "Testing QueryAllCertificates query..."
peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CHAINCODE_NAME" \
    -c '{"function":"QueryAllCertificates","Args":[]}' \
    2>&1 | tail -3

# ══════════════════════════════════════════════════════════════════════════════
# STEP 6: Display Network Information
# ══════════════════════════════════════════════════════════════════════════════
header "Step 6: Network Information"

echo -e "${GREEN}✅ Network is ready and Smart Contract is deployed!${NC}"
echo ""
echo -e "${YELLOW}📂 Now you can run Caliper using:${NC}"
echo "   cd $PROJECT_ROOT/caliper-workspace"
echo "   chmod +x fix_and_run_caliper.sh"
echo "   ./fix_and_run_caliper.sh"
echo ""
echo -e "${YELLOW}🌐 Network Endpoints:${NC}"
echo "   Orderer  : localhost:7050 (TLS)"
echo "   Org1 Peer: localhost:7051 (TLS)"
echo "   Org2 Peer: localhost:9051 (TLS)"
echo "   CA Org1  : localhost:7054"
echo "   CA Org2  : localhost:8054"
echo ""
echo -e "${YELLOW}📋 Chaincode Details:${NC}"
echo "   Name    : $CHAINCODE_NAME"
echo "   Channel : $CHANNEL_NAME"
echo "   Language: Go (fabric-contract-api-go)"
echo "   Version : $CHAINCODE_VERSION"
