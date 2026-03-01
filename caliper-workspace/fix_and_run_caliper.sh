#!/bin/bash
# ============================================================
# fix_and_run_caliper.sh
# BCMS Certificate Benchmark Runner — v3.0
#
# USAGE (from caliper-workspace directory):
#   chmod +x fix_and_run_caliper.sh
#   ./fix_and_run_caliper.sh
#
# WHAT THIS SCRIPT DOES:
#   1. Locates dynamic private keys and certificates
#   2. Injects correct paths into networkConfig.yaml
#   3. Injects correct TLS cert paths into connection profiles
#   4. Installs Caliper CLI (if not already installed)
#   5. Runs Caliper benchmark (4 rounds)
#   6. Opens the HTML report
#
# FIXES APPLIED (Root Cause Analysis from previous runs):
#   FIX 1: discover:false → Prevents RoundRobinQueryHandler error
#   FIX 2: Dynamic key paths → No more "private key not found" error
#   FIX 3: Correct function signatures → No argument mismatch
#   FIX 4: Idempotent chaincode → No spurious failures under load
#   FIX 5: Org2 identity → RevokeCertificate uses correct MSP
# ============================================================

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗] ERROR: $1${NC}"; exit 1; }
info()   { echo -e "${CYAN}[→]${NC} $1"; }
header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
}

# ── Paths ─────────────────────────────────────────────────────────────────────
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$WORKSPACE_DIR")"
FABRIC_HOME="${FABRIC_HOME:-$HOME/fabric-samples}"
TEST_NETWORK_PATH="$FABRIC_HOME/test-network"
NETWORK_CONFIG="$WORKSPACE_DIR/networkConfig.yaml"
CONN_ORG1="$WORKSPACE_DIR/networks/connection-org1.yaml"
CONN_ORG2="$WORKSPACE_DIR/networks/connection-org2.yaml"

header "Hyperledger Caliper — BCMS Benchmark v3.0"
echo -e "  Target: 0 Failures across all 4 rounds"
echo ""
echo -e "  ROOT_DIR  : ${YELLOW}$ROOT_DIR${NC}"
echo -e "  WORKSPACE : ${YELLOW}$WORKSPACE_DIR${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: Locate Org1 Private Key (Dynamic)
# ══════════════════════════════════════════════════════════════════════════════
header "Step 1: Locating Cryptographic Material"

ORG1_MSP_DIR="$TEST_NETWORK_PATH/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp"
ORG2_MSP_DIR="$TEST_NETWORK_PATH/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp"

info "Searching for Org1 private key..."
ORG1_KEY=$(find "$ORG1_MSP_DIR/keystore" -name "*_sk" -type f 2>/dev/null | head -1)
if [ -z "$ORG1_KEY" ]; then
    error "Org1 private key not found in: $ORG1_MSP_DIR/keystore
    
    Possible causes:
      1. Network is not running — run: cd $TEST_NETWORK_PATH && ./network.sh up createChannel -ca -c mychannel -s couchdb
      2. Certificates were not generated — run with -ca flag
      3. Path is different — check: ls $ORG1_MSP_DIR/keystore/"
fi
log "Org1 Key  : $ORG1_KEY"

info "Searching for Org1 certificate..."
ORG1_CERT=$(find "$ORG1_MSP_DIR/signcerts" -name "*.pem" -type f 2>/dev/null | head -1)
if [ -z "$ORG1_CERT" ]; then
    # Fallback: try User1@org1.example.com-cert.pem pattern
    ORG1_CERT=$(find "$ORG1_MSP_DIR/signcerts" -type f 2>/dev/null | head -1)
fi
if [ -z "$ORG1_CERT" ]; then
    error "Org1 certificate not found in: $ORG1_MSP_DIR/signcerts"
fi
log "Org1 Cert : $ORG1_CERT"

info "Searching for Org2 private key..."
ORG2_KEY=$(find "$ORG2_MSP_DIR/keystore" -name "*_sk" -type f 2>/dev/null | head -1)
if [ -z "$ORG2_KEY" ]; then
    error "Org2 private key not found in: $ORG2_MSP_DIR/keystore
    
    Ensure network was started with -ca flag and Org2 CA is running."
fi
log "Org2 Key  : $ORG2_KEY"

info "Searching for Org2 certificate..."
ORG2_CERT=$(find "$ORG2_MSP_DIR/signcerts" -name "*.pem" -type f 2>/dev/null | head -1)
if [ -z "$ORG2_CERT" ]; then
    ORG2_CERT=$(find "$ORG2_MSP_DIR/signcerts" -type f 2>/dev/null | head -1)
fi
if [ -z "$ORG2_CERT" ]; then
    error "Org2 certificate not found in: $ORG2_MSP_DIR/signcerts"
fi
log "Org2 Cert : $ORG2_CERT"

# TLS certificates
ORG1_TLS_CERT="$TEST_NETWORK_PATH/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_TLS_CERT="$TEST_NETWORK_PATH/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
ORDERER_TLS_CERT="$TEST_NETWORK_PATH/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
CA_ORG1_CERT="$TEST_NETWORK_PATH/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem"
CA_ORG2_CERT="$TEST_NETWORK_PATH/organizations/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem"

# Validate TLS certs
[ -f "$ORG1_TLS_CERT" ] || error "Org1 TLS cert not found: $ORG1_TLS_CERT"
[ -f "$ORG2_TLS_CERT" ] || error "Org2 TLS cert not found: $ORG2_TLS_CERT"
[ -f "$ORDERER_TLS_CERT" ] || error "Orderer TLS cert not found: $ORDERER_TLS_CERT"

log "All TLS certificates found."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: Inject Dynamic Paths into networkConfig.yaml
# ══════════════════════════════════════════════════════════════════════════════
header "Step 2: Injecting Dynamic Certificate Paths (FIX #2)"

# Backup original
cp "$NETWORK_CONFIG" "${NETWORK_CONFIG}.bak" 2>/dev/null || true

# Replace DYNAMIC placeholders with actual paths
sed -i \
    -e "s|DYNAMIC_ORG1_PRIVATE_KEY|$ORG1_KEY|g" \
    -e "s|DYNAMIC_ORG1_CERT|$ORG1_CERT|g" \
    -e "s|DYNAMIC_ORG2_PRIVATE_KEY|$ORG2_KEY|g" \
    -e "s|DYNAMIC_ORG2_CERT|$ORG2_CERT|g" \
    "$NETWORK_CONFIG"

log "networkConfig.yaml updated with dynamic key paths."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: Inject TLS Cert Paths into Connection Profiles
# ══════════════════════════════════════════════════════════════════════════════
header "Step 3: Injecting TLS Certificate Paths"

# Org1 connection profile
cp "$CONN_ORG1" "${CONN_ORG1}.bak" 2>/dev/null || true
sed -i \
    -e "s|DYNAMIC_ORG1_TLS_CERT|$ORG1_TLS_CERT|g" \
    -e "s|DYNAMIC_ORDERER_TLS_CERT|$ORDERER_TLS_CERT|g" \
    -e "s|DYNAMIC_CA_ORG1_CERT|$CA_ORG1_CERT|g" \
    "$CONN_ORG1"
log "connection-org1.yaml TLS paths injected."

# Org2 connection profile
cp "$CONN_ORG2" "${CONN_ORG2}.bak" 2>/dev/null || true
sed -i \
    -e "s|DYNAMIC_ORG2_TLS_CERT|$ORG2_TLS_CERT|g" \
    -e "s|DYNAMIC_ORDERER_TLS_CERT|$ORDERER_TLS_CERT|g" \
    -e "s|DYNAMIC_CA_ORG2_CERT|$CA_ORG2_CERT|g" \
    "$CONN_ORG2"
log "connection-org2.yaml TLS paths injected."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: Verify Network is Running
# ══════════════════════════════════════════════════════════════════════════════
header "Step 4: Verifying Network Status"

PEER_COUNT=$(docker ps --filter "name=peer" --format "{{.Names}}" 2>/dev/null | wc -l)
ORDERER_COUNT=$(docker ps --filter "name=orderer" --format "{{.Names}}" 2>/dev/null | wc -l)

if [ "$PEER_COUNT" -lt 2 ] || [ "$ORDERER_COUNT" -lt 1 ]; then
    warn "Network containers not fully running (Peers: $PEER_COUNT, Orderers: $ORDERER_COUNT)"
    warn "Starting network now..."
    
    cd "$TEST_NETWORK_PATH"
    ./network.sh down 2>/dev/null || true
    ./network.sh up createChannel -ca -c mychannel -s couchdb
    
    # Deploy chaincode
    ./network.sh deployCC \
        -ccn basic \
        -ccp "$ROOT_DIR/chaincode/basic" \
        -ccl go \
        -ccv 1.0 \
        -ccs 1
    
    cd "$WORKSPACE_DIR"
    log "Network started and chaincode deployed."
else
    log "Network running: ${PEER_COUNT} peer(s), ${ORDERER_COUNT} orderer(s)."
fi

# Verify chaincode is deployed
export PATH="$FABRIC_HOME/bin:$PATH"
export FABRIC_CFG_PATH="$FABRIC_HOME/config"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="$ORG1_TLS_CERT"
export CORE_PEER_MSPCONFIGPATH="$TEST_NETWORK_PATH/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS="localhost:7051"

info "Verifying chaincode 'basic' is committed on mychannel..."
if ! peer lifecycle chaincode querycommitted \
    --channelID mychannel \
    --name basic \
    --tls \
    --cafile "$ORDERER_TLS_CERT" \
    --output json 2>/dev/null | grep -q '"name":"basic"'; then
    
    warn "Chaincode not found. Deploying now..."
    cd "$TEST_NETWORK_PATH"
    ./network.sh deployCC \
        -ccn basic \
        -ccp "$ROOT_DIR/chaincode/basic" \
        -ccl go \
        -ccv 1.0 \
        -ccs 1
    cd "$WORKSPACE_DIR"
    log "Chaincode deployed."
else
    log "Chaincode 'basic' is committed on channel 'mychannel'"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5: Install / Verify Caliper CLI
# ══════════════════════════════════════════════════════════════════════════════
header "Step 5: Setting Up Caliper CLI"

cd "$WORKSPACE_DIR"

if [ ! -f "package.json" ]; then
    info "Initializing npm package..."
    npm init -y
fi

# Check if caliper is installed
if ! npx --no-install caliper --version &>/dev/null 2>&1; then
    info "Installing Caliper CLI and Fabric adapter..."
    npm install --save-dev \
        @hyperledger/caliper-cli@0.6.0 \
        @hyperledger/caliper-fabric@0.6.0
    log "Caliper installed successfully."
else
    log "Caliper CLI already installed."
fi

# Bind Caliper to Fabric SDK
info "Binding Caliper to Hyperledger Fabric SDK..."
npx caliper bind --caliper-bind-sut fabric:fabric-gateway 2>/dev/null || \
npx caliper bind --caliper-bind-sut fabric:2.4 2>/dev/null || \
warn "Bind step skipped (may already be bound)."

log "Caliper setup complete."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 6: Run Caliper Benchmark
# ══════════════════════════════════════════════════════════════════════════════
header "Step 6: Running Caliper Benchmark (4 Rounds)"

info "This will take approximately 2-3 minutes (4 rounds × 30s each)"
echo ""
echo -e "  Round 1: IssueCertificate    — 50 TPS × 30s"
echo -e "  Round 2: VerifyCertificate   — 100 TPS × 30s"
echo -e "  Round 3: QueryAllCertificates — 50 TPS × 30s"
echo -e "  Round 4: RevokeCertificate   — 50 TPS × 30s"
echo ""

# Timestamp for report naming
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$WORKSPACE_DIR/report_${TIMESTAMP}.html"

# Run Caliper with Gateway mode enabled
npx caliper launch manager \
    --caliper-workspace "$WORKSPACE_DIR" \
    --caliper-benchconfig benchconfig.yaml \
    --caliper-networkconfig networkConfig.yaml \
    --caliper-fabric-gateway-enabled \
    --caliper-report-path "$REPORT_FILE" \
    2>&1

# ══════════════════════════════════════════════════════════════════════════════
# STEP 7: Report
# ══════════════════════════════════════════════════════════════════════════════
header "Step 7: Benchmark Complete"

if [ -f "$REPORT_FILE" ]; then
    log "Report generated: $REPORT_FILE"
    echo ""
    echo -e "${GREEN}✅ Benchmark Complete!${NC}"
    echo -e "   Report saved to: ${YELLOW}$REPORT_FILE${NC}"
    
    # Try to open report in browser
    if command -v xdg-open &>/dev/null; then
        xdg-open "$REPORT_FILE" 2>/dev/null || true
    elif command -v open &>/dev/null; then
        open "$REPORT_FILE" 2>/dev/null || true
    else
        info "Open the report manually: $REPORT_FILE"
    fi
else
    # Look for default report
    DEFAULT_REPORT="$WORKSPACE_DIR/report.html"
    if [ -f "$DEFAULT_REPORT" ]; then
        log "Report found at: $DEFAULT_REPORT"
    else
        warn "Report file not found. Check for errors above."
    fi
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  BCMS Benchmark Finished Successfully!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
