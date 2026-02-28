#!/bin/bash
################################################################################
# fix_and_run_caliper.sh
# ─────────────────────────────────────────────────────────────────────────────
# Automated Caliper Fix & Run Script
# Project: BCMS (Blockchain Certificate Management System)
# Version: 3.0 — Zero-Failure Design
#
# What this script does:
#   1. Validates the Fabric test-network is running
#   2. Dynamically finds private key paths (handles the hash-named key file)
#   3. Generates networkConfig.yaml + connection profiles with correct paths
#   4. Installs Caliper + binds to Fabric 2.5
#   5. Runs the 4-round benchmark
#   6. Opens report.html for review
#
# Usage:
#   cd caliper-workspace
#   bash fix_and_run_caliper.sh [ROOT_DIR]
#
# ROOT_DIR defaults to the parent of this script's parent directory,
# which is the fabric-samples / fabric_certificate_new repo root.
################################################################################

set -euo pipefail

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}ℹ️  $*${RESET}"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}❌ $*${RESET}"; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }

# ─── Script location ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─── ROOT_DIR: repo root (one level above caliper-workspace) ──────────────────
ROOT_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
info "ROOT_DIR = $ROOT_DIR"
info "CALIPER_WORKSPACE = $SCRIPT_DIR"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   BCMS Caliper Benchmark — Automated Fix & Run (v3.0)       ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: Validate test-network is up
# ══════════════════════════════════════════════════════════════════════════════
step "STEP 1: Validating Fabric test-network"

PEER_ORG1="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com"
PEER_ORG2="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com"
ORDERER_DIR="$ROOT_DIR/test-network/organizations/ordererOrganizations/example.com"

if [ ! -d "$PEER_ORG1" ]; then
    error "Org1 crypto material not found at $PEER_ORG1\nRun: cd $ROOT_DIR/test-network && ./network.sh up createChannel -ca && ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go"
fi

if [ ! -d "$PEER_ORG2" ]; then
    error "Org2 crypto material not found at $PEER_ORG2"
fi

success "test-network crypto material found"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: Dynamically find key files
# ══════════════════════════════════════════════════════════════════════════════
step "STEP 2: Locating identity key files"

# Org1 User1 private key (file name contains a random hash)
ORG1_KEY=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/keystore" \
           -maxdepth 1 -name "*_sk" -o -name "*.pem" 2>/dev/null | head -n 1)
[ -z "$ORG1_KEY" ] && error "Org1 User1 private key not found in keystore"
success "Org1 key: $ORG1_KEY"

ORG1_CERT="$PEER_ORG1/users/User1@org1.example.com/msp/signcerts/User1@org1.example.com-cert.pem"
[ ! -f "$ORG1_CERT" ] && \
    ORG1_CERT=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/signcerts" -name "*.pem" | head -1)
[ -z "$ORG1_CERT" ] && error "Org1 User1 certificate not found"
success "Org1 cert: $ORG1_CERT"

# Org2 User1 private key
ORG2_KEY=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/keystore" \
           -maxdepth 1 -name "*_sk" -o -name "*.pem" 2>/dev/null | head -n 1)
[ -z "$ORG2_KEY" ] && error "Org2 User1 private key not found in keystore"
success "Org2 key: $ORG2_KEY"

ORG2_CERT="$PEER_ORG2/users/User1@org2.example.com/msp/signcerts/User1@org2.example.com-cert.pem"
[ ! -f "$ORG2_CERT" ] && \
    ORG2_CERT=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/signcerts" -name "*.pem" | head -1)
[ -z "$ORG2_CERT" ] && error "Org2 User1 certificate not found"
success "Org2 cert: $ORG2_CERT"

# TLS CA certs
ORG1_TLS_CA="$PEER_ORG1/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_TLS_CA="$PEER_ORG2/peers/peer0.org2.example.com/tls/ca.crt"
ORDERER_TLS_CA="$ORDERER_DIR/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORG1_CA_CERT="$PEER_ORG1/ca/ca.org1.example.com-cert.pem"
ORG2_CA_CERT="$PEER_ORG2/ca/ca.org2.example.com-cert.pem"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: Generate networkConfig.yaml with real paths
# ══════════════════════════════════════════════════════════════════════════════
step "STEP 3: Generating networks/networkConfig.yaml"

mkdir -p networks

cat > networks/networkConfig.yaml << NETCFG
################################################################################
# Generated by fix_and_run_caliper.sh — DO NOT EDIT MANUALLY
# Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
################################################################################
name: "BCMS-Certificate-Network"
version: "2.0.0"

caliper:
  blockchain: fabric

channels:
  - channelName: mychannel
    contracts:
      - id: basic
        contractID: basic

organizations:

  - mspid: Org1MSP
    identities:
      certificates:
        - name: "User1@org1.example.com"
          clientPrivateKey:
            path: "$ORG1_KEY"
          clientSignedCert:
            path: "$ORG1_CERT"
    connectionProfile:
      path: "networks/connection-org1.yaml"
      discover: false

  - mspid: Org2MSP
    identities:
      certificates:
        - name: "User1@org2.example.com"
          clientPrivateKey:
            path: "$ORG2_KEY"
          clientSignedCert:
            path: "$ORG2_CERT"
    connectionProfile:
      path: "networks/connection-org2.yaml"
      discover: false
NETCFG

success "networkConfig.yaml generated"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: Generate connection-org1.yaml
# ══════════════════════════════════════════════════════════════════════════════
step "STEP 4: Generating networks/connection-org1.yaml"

cat > networks/connection-org1.yaml << CONN1
name: "test-network-org1"
version: "1.0.0"
client:
  organization: Org1
  connection:
    timeout:
      peer:
        endorser: "300"
      orderer: "300"
channels:
  mychannel:
    orderers:
      - orderer.example.com
    peers:
      peer0.org1.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true
      peer0.org2.example.com:
        endorsingPeer: true
        chaincodeQuery: false
        ledgerQuery: false
        eventSource: false
organizations:
  Org1:
    mspid: Org1MSP
    peers:
      - peer0.org1.example.com
    certificateAuthorities:
      - ca.org1.example.com
  Org2:
    mspid: Org2MSP
    peers:
      - peer0.org2.example.com
orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
      hostnameOverride: orderer.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 20000
      grpc.http2.min_time_between_pings_ms: 120000
      grpc.http2.max_pings_without_data: 0
    tlsCACerts:
      path: "$ORDERER_TLS_CA"
peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts:
      path: "$ORG1_TLS_CA"
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts:
      path: "$ORG2_TLS_CA"
certificateAuthorities:
  ca.org1.example.com:
    url: https://localhost:7054
    caName: ca-org1
    tlsCACerts:
      path: "$ORG1_CA_CERT"
    httpOptions:
      verify: false
CONN1

success "connection-org1.yaml generated"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5: Generate connection-org2.yaml
# ══════════════════════════════════════════════════════════════════════════════
step "STEP 5: Generating networks/connection-org2.yaml"

cat > networks/connection-org2.yaml << CONN2
name: "test-network-org2"
version: "1.0.0"
client:
  organization: Org2
  connection:
    timeout:
      peer:
        endorser: "300"
      orderer: "300"
channels:
  mychannel:
    orderers:
      - orderer.example.com
    peers:
      peer0.org2.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true
      peer0.org1.example.com:
        endorsingPeer: true
        chaincodeQuery: false
        ledgerQuery: false
        eventSource: false
organizations:
  Org1:
    mspid: Org1MSP
    peers:
      - peer0.org1.example.com
  Org2:
    mspid: Org2MSP
    peers:
      - peer0.org2.example.com
    certificateAuthorities:
      - ca.org2.example.com
orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
      hostnameOverride: orderer.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 20000
      grpc.http2.min_time_between_pings_ms: 120000
      grpc.http2.max_pings_without_data: 0
    tlsCACerts:
      path: "$ORDERER_TLS_CA"
peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts:
      path: "$ORG1_TLS_CA"
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts:
      path: "$ORG2_TLS_CA"
certificateAuthorities:
  ca.org2.example.com:
    url: https://localhost:8054
    caName: ca-org2
    tlsCACerts:
      path: "$ORG2_CA_CERT"
    httpOptions:
      verify: false
CONN2

success "connection-org2.yaml generated"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 6: Install node dependencies + bind to Fabric 2.5
# ══════════════════════════════════════════════════════════════════════════════
step "STEP 6: Installing Caliper dependencies"

npm install --quiet

step "Binding Caliper to Fabric 2.5"
npx caliper bind \
    --caliper-bind-sut fabric:2.5 \
    --caliper-bind-cwd ./ \
    --caliper-bind-args="-g" 2>&1 | tail -5

success "Caliper bound to fabric:2.5"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 7: Run the benchmark
# ══════════════════════════════════════════════════════════════════════════════
step "STEP 7: Launching Caliper Benchmark (4 rounds × 30s each)"
info "Estimated runtime: ~3 minutes"
echo ""

npx caliper launch manager \
    --caliper-workspace ./ \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

BENCHMARK_EXIT=$?

# ══════════════════════════════════════════════════════════════════════════════
# STEP 8: Results summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║                   BENCHMARK COMPLETED                       ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

if [ $BENCHMARK_EXIT -eq 0 ]; then
    success "All rounds completed — check report.html for results"
    info "Quick metrics preview:"
    if [ -f report.html ]; then
        grep -oP '(?<=<td>)\d+(?=</td>)' report.html | head -20 || true
    fi
else
    warn "Caliper exited with code $BENCHMARK_EXIT — review output above"
fi

echo ""
info "Report location: $SCRIPT_DIR/report.html"
echo ""
