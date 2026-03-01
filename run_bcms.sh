#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  BCMS — Blockchain Certificate Management System                            ║
# ║  Main Execution Script v5.0                                                 ║
# ║  ─────────────────────────────────────────────────────────────────────────  ║
# ║  الهدف: تشغيل شبكة Hyperledger Fabric + نشر Chaincode RBAC + Caliper       ║
# ║  نسبة الفشل المستهدفة: 0%  (Fail = 0 across all 4 rounds)                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# الألوان والدوال المساعدة
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK_DIR="$ROOT_DIR/test-network"
CALIPER_DIR="$ROOT_DIR/caliper-workspace"
CHAINCODE_DIR="$ROOT_DIR/asset-transfer-basic/chaincode-go"
LOG_FILE="$ROOT_DIR/bcms_run.log"
REPORT_FILE="$CALIPER_DIR/report.html"

log()      { echo -e "${GREEN}[✅ OK]${NC} $*" | tee -a "$LOG_FILE"; }
warn()     { echo -e "${YELLOW}[⚠️  WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error()    { echo -e "${RED}[❌ ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
info()     { echo -e "${BLUE}[ℹ️  INFO]${NC} $*" | tee -a "$LOG_FILE"; }
step()     { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"; }
divider()  { echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"; }

# ─────────────────────────────────────────────────────────────────────────────
# تهيئة ملف السجل
# ─────────────────────────────────────────────────────────────────────────────
echo "" > "$LOG_FILE"
divider
echo -e "${BOLD}  🔗 BCMS — Blockchain Certificate Management System${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}  📅 $(date '+%Y-%m-%d %H:%M:%S')${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}  🎯 Target: Fail = 0 across all Caliper rounds${NC}" | tee -a "$LOG_FILE"
divider

# ─────────────────────────────────────────────────────────────────────────────
# Step 0: إصلاح الصلاحيات (في بيئة CI تلقائياً)
# ─────────────────────────────────────────────────────────────────────────────
step "Step 0: Permissions & Environment Check"

if [ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ "${FIX_PERMISSIONS:-}" = "true" ]; then
    if [ -x "$ROOT_DIR/scripts/fix-permissions.sh" ]; then
        info "Running fix-permissions.sh (CI environment detected)..."
        "$ROOT_DIR/scripts/fix-permissions.sh" || warn "Permission fix returned non-zero (continuing)"
    fi
fi

# التحقق من أدوات Fabric
if [ ! -d "$ROOT_DIR/bin" ]; then
    warn "Fabric binaries not found. Downloading..."
    cd "$ROOT_DIR"
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7 --docker-images=false
    log "Fabric binaries downloaded"
else
    log "Fabric binaries found"
fi

export PATH="$ROOT_DIR/bin:$PATH"
export FABRIC_CFG_PATH="$ROOT_DIR/config/"

# التحقق من Docker
if ! command -v docker &>/dev/null; then
    error "Docker not found. Please install Docker Desktop."
    exit 1
fi
log "Docker available: $(docker --version)"

# التحقق من Node.js
if ! command -v node &>/dev/null; then
    error "Node.js not found."
    exit 1
fi
log "Node.js available: $(node --version)"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: تنظيف بيئة Docker القديمة
# ─────────────────────────────────────────────────────────────────────────────
step "Step 1: Cleaning Old Docker Environment"

cd "$NETWORK_DIR"
./network.sh down 2>/dev/null || warn "network.sh down returned non-zero (safe to ignore)"

# إزالة صور chaincode القديمة
DEV_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '^dev-' || true)
if [ -n "$DEV_IMAGES" ]; then
    echo "$DEV_IMAGES" | xargs docker rmi -f 2>/dev/null || true
    log "Removed old chaincode Docker images"
else
    info "No old chaincode images found"
fi

# مسح تقرير Caliper القديم
rm -f "$REPORT_FILE"
rm -f "$CALIPER_DIR/networks/networkConfig.yaml"

log "Environment cleaned"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: تشغيل الشبكة مع CouchDB
# ─────────────────────────────────────────────────────────────────────────────
step "Step 2: Starting Hyperledger Fabric Test Network (CouchDB)"

cd "$NETWORK_DIR"
./network.sh up createChannel -c mychannel -ca -s couchdb

info "Waiting 20 seconds for network to stabilize..."
sleep 20

log "Network is UP — Channel: mychannel"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: نشر العقد الذكي مع RBAC
# ─────────────────────────────────────────────────────────────────────────────
step "Step 3: Deploying RBAC Certificate Chaincode"

echo ""
echo -e "${BOLD}  Smart Contract Functions:${NC}"
echo -e "  ${GREEN}1. IssueCertificate${NC}     — Org1 RBAC Write"
echo -e "  ${GREEN}2. VerifyCertificate${NC}    — Public Read"
echo -e "  ${GREEN}3. QueryAllCertificates${NC} — Public Read"
echo -e "  ${GREEN}4. RevokeCertificate${NC}    — Org1/Org2 RBAC Write"
echo -e "  ${GREEN}5. CertificateExists${NC}    — Helper"
echo ""

cd "$NETWORK_DIR"
./network.sh deployCC \
    -ccn basic \
    -ccp "$CHAINCODE_DIR" \
    -ccl go \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

log "Chaincode deployed: basic"
info "Waiting 10 seconds for chaincode to initialize..."
sleep 10

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: استخراج مفاتيح الهوية لـ Caliper
# ─────────────────────────────────────────────────────────────────────────────
step "Step 4: Resolving Org Identity Keys for Caliper"

PEER_ORG1="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com"
PEER_ORG2="$NETWORK_DIR/organizations/peerOrganizations/org2.example.com"

if [ ! -d "$PEER_ORG1" ]; then
    error "Org1 crypto material not found at: $PEER_ORG1"
    exit 1
fi
if [ ! -d "$PEER_ORG2" ]; then
    error "Org2 crypto material not found at: $PEER_ORG2"
    exit 1
fi

ORG1_KEY=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/keystore" -name "*_sk" 2>/dev/null | head -1)
ORG2_KEY=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/keystore" -name "*_sk" 2>/dev/null | head -1)

ORG1_CERT="$PEER_ORG1/users/User1@org1.example.com/msp/signcerts/cert.pem"
ORG2_CERT="$PEER_ORG2/users/User1@org2.example.com/msp/signcerts/cert.pem"

# Fallback for cert path variations
if [ ! -f "$ORG1_CERT" ]; then
    ORG1_CERT=$(find "$PEER_ORG1/users/User1@org1.example.com/msp/signcerts" -name "*.pem" 2>/dev/null | head -1)
fi
if [ ! -f "$ORG2_CERT" ]; then
    ORG2_CERT=$(find "$PEER_ORG2/users/User1@org2.example.com/msp/signcerts" -name "*.pem" 2>/dev/null | head -1)
fi

[ -z "$ORG1_KEY"  ] && { error "Org1 private key not found"; exit 1; }
[ -z "$ORG2_KEY"  ] && { error "Org2 private key not found"; exit 1; }
[ -z "$ORG1_CERT" ] && { error "Org1 cert not found"; exit 1; }
[ -z "$ORG2_CERT" ] && { error "Org2 cert not found"; exit 1; }

log "Org1 key:  $ORG1_KEY"
log "Org2 key:  $ORG2_KEY"
log "Org1 cert: $ORG1_CERT"
log "Org2 cert: $ORG2_CERT"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: توليد networkConfig.yaml لـ Caliper
# ─────────────────────────────────────────────────────────────────────────────
step "Step 5: Generating Caliper networkConfig.yaml"

cd "$CALIPER_DIR"
mkdir -p networks

cat > networks/networkConfig.yaml <<NETCFG
################################################################################
# Caliper Network Configuration — BCMS
# Auto-generated by run_bcms.sh on $(date '+%Y-%m-%d %H:%M:%S')
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

  # ── Org1 — Issues Certificates (RBAC) ───────────────────────────────────
  - mspid: Org1MSP
    identities:
      certificates:
        - name: "User1@org1.example.com"
          clientPrivateKey:
            path: "$ORG1_KEY"
          clientSignedCert:
            path: "$ORG1_CERT"
    connectionProfile:
      path: "$PEER_ORG1/connection-org1.yaml"
      discover: false

  # ── Org2 — Revokes Certificates (RBAC) ──────────────────────────────────
  - mspid: Org2MSP
    identities:
      certificates:
        - name: "User1@org2.example.com"
          clientPrivateKey:
            path: "$ORG2_KEY"
          clientSignedCert:
            path: "$ORG2_CERT"
    connectionProfile:
      path: "$PEER_ORG2/connection-org2.yaml"
      discover: false
NETCFG

log "networkConfig.yaml generated"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: تثبيت Caliper وربطه بـ Fabric
# ─────────────────────────────────────────────────────────────────────────────
step "Step 6: Installing & Binding Caliper to Fabric"

cd "$CALIPER_DIR"

if [ ! -d "node_modules" ]; then
    info "Installing npm dependencies..."
    npm install --quiet
    log "npm install done"
else
    log "node_modules already exist"
fi

info "Binding Caliper to Fabric 2.5..."
npx caliper bind --caliper-bind-sut fabric:2.5
log "Caliper bound to Fabric 2.5"

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: تشغيل Benchmark Caliper (4 rounds — Fail = 0)
# ─────────────────────────────────────────────────────────────────────────────
step "Step 7: Running Caliper Benchmark (4 Rounds — Target: Fail = 0)"

echo ""
echo -e "${BOLD}  Benchmark Rounds:${NC}"
echo -e "  ${CYAN}Round 1:${NC} IssueCertificate     @ 10 TPS / 30s  [Org1 RBAC Write]"
echo -e "  ${CYAN}Round 2:${NC} VerifyCertificate    @ 20 TPS / 30s  [Public Read]"
echo -e "  ${CYAN}Round 3:${NC} QueryAllCertificates @ 20 TPS / 30s  [Public Read]"
echo -e "  ${CYAN}Round 4:${NC} RevokeCertificate    @ 10 TPS / 30s  [Org2 RBAC Write]"
echo ""

cd "$CALIPER_DIR"

npx caliper launch manager \
    --caliper-workspace ./ \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig  benchmarks/benchConfig.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: التحقق من التقرير وعرض الملخص
# ─────────────────────────────────────────────────────────────────────────────
step "Step 8: Report Validation & Summary"

if [ -f "$REPORT_FILE" ]; then
    REPORT_SIZE=$(du -k "$REPORT_FILE" | cut -f1)
    log "Caliper HTML report generated: $REPORT_FILE (${REPORT_SIZE}KB)"
    
    # استخراج إحصائيات الفشل من التقرير
    if grep -q '"Fail"' "$REPORT_FILE" 2>/dev/null; then
        FAIL_COUNT=$(grep -o '"Fail":[0-9]*' "$REPORT_FILE" | grep -v ':0' | wc -l || echo "0")
        if [ "$FAIL_COUNT" -eq 0 ]; then
            log "🎉 ZERO FAILURES detected in all rounds!"
        else
            warn "Some failures detected. Check report: $REPORT_FILE"
        fi
    fi
else
    warn "Report file not found at expected location"
fi

divider
echo -e "${BOLD}${GREEN}"
echo "  ✅ BCMS Execution Complete!"
echo ""
echo "  📊 Caliper Report: $REPORT_FILE"
echo "  📝 Run Log:        $LOG_FILE"
echo ""
echo "  Network Architecture:"
echo "  ├── Channel:    mychannel"
echo "  ├── Orgs:       Org1MSP (issuer) + Org2MSP (revoker)"
echo "  ├── Chaincode:  basic (RBAC Certificate Management)"
echo "  └── DB Backend: CouchDB"
echo -e "${NC}"
divider

echo ""
echo -e "${YELLOW}📖 To view the Caliper report, open in browser:${NC}"
echo "   file://$REPORT_FILE"
echo ""
echo -e "${YELLOW}🛑 To stop the network:${NC}"
echo "   cd test-network && ./network.sh down"
echo ""
