#!/bin/bash
set -e

# تشغيل سكربت إصلاح الصلاحيات فقط في بيئة CI أو عند طلب صريح عبر FIX_PERMISSIONS
# يمكن فرض التشغيل محليًا بتشغيل: FIX_PERMISSIONS=true ./setup_and_run_all.sh
if [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ "${FIX_PERMISSIONS:-}" = "true" ]; then
  if [ -x "./scripts/fix-permissions.sh" ]; then
    echo "🔐 Running scripts/fix-permissions.sh to fix permissions (CI or FIX_PERMISSIONS set)..."
    ./scripts/fix-permissions.sh || true
  else
    echo "⚠️ scripts/fix-permissions.sh not found or not executable. Skipping."
  fi
else
  echo "ℹ️ Not in CI and FIX_PERMISSIONS not set; skipping permission fix."
fi

# مسح أي حاويات أو شبكات قديمة متبقية بالقوة
docker rm -f $(docker ps -aq) || true
docker volume prune -f

# Deep Clean: إزالة صور Docker التي تبدأ بـ dev-* أو dev-peer*
echo -e "\n🧹 Performing deep-clean for Docker images starting with dev-*..."
DEV_IMAGE_IDS=$(docker images --format '{{.Repository}} {{.ID}}' | awk '$1 ~ /^(dev-|dev-peer)/ {print $2}' || true)
if [ -n "$DEV_IMAGE_IDS" ]; then
  echo "Found dev images: $DEV_IMAGE_IDS"
  docker rmi -f $DEV_IMAGE_IDS || true
else
  echo "No dev-* images found."
fi

# مسح التقارير القديمة
rm -f caliper-workspace/report.html

# التأكد من تحديث الـ Workspace
cd caliper-workspace && rm -rf networks/networkConfig.yaml && cd ..

# تعريف الألوان للنصوص
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting Full Project Setup (Fabric + Caliper)...${NC}"
echo "=================================================="
echo "📋 Smart Contract Functions:"
echo "   1️⃣  IssueCertificate     (Org1 Only)   - إصدار شهادة"
echo "   2️⃣  VerifyCertificate    (Public Read) - التحقق من شهادة"
echo "   3️⃣  QueryAllCertificates (Public Read) - استعلام كل الشهادات"
echo "   4️⃣  RevokeCertificate    (Org2 Auth)   - إلغاء شهادة"
echo "   5️⃣  CertificateExists    (Helper)      - التحقق من الوجود"
echo "=================================================="

# التأكد من وجود الأدوات
echo -e "${GREEN}📦 Step 1: Checking Fabric Binaries...${NC}"
if [ ! -d "bin" ]; then
  echo "⬇️ Downloading Fabric tools..."
  curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
  echo "✅ Fabric tools found."
fi

export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# تشغيل الشبكة
echo -e "${GREEN}🌐 Step 2: Starting Test Network...${NC}"
cd test-network
./network.sh down
docker volume prune -f
docker system prune -f
./network.sh up createChannel -c mychannel -ca -s couchdb

# انتظار استقرار CouchDB
echo "⏳ Waiting 30 seconds for CouchDB and Peers to stabilize..."
sleep 30
cd ..

# نشر العقد الذكي (يتضمن الآن 5 دوال)
echo -e "${GREEN}📜 Step 3: Deploying Smart Contract...${NC}"
echo "   Functions: IssueCertificate | VerifyCertificate | QueryAllCertificates | RevokeCertificate | CertificateExists"
cd test-network
./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go -ccep "OR('Org1MSP.peer','Org2MSP.peer')"
cd ..

# تشغيل Caliper
echo -e "${GREEN}📊 Step 4: Running Caliper Benchmark...${NC}"
cd caliper-workspace
if [ ! -d "node_modules" ]; then
  npm install
  npx caliper bind --caliper-bind-sut fabric:2.2
fi

echo "🔑 Detecting Private Keys..."
# Org1 Key
KEY_DIR1="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY1=$(ls $KEY_DIR1/*_sk)
# Org2 Key
KEY_DIR2="../test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
PVT_KEY2=$(ls $KEY_DIR2/*_sk)

echo "Org1 Key: $PVT_KEY1"
echo "Org2 Key: $PVT_KEY2"

# إنشاء ملف إعدادات الشبكة
echo "⚙️ Generating network config..."
mkdir -p networks

cat << EOF > networks/networkConfig.yaml
name: Caliper-Fabric
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
        - name: 'User1@org1.example.com'
          clientPrivateKey:
            path: '$PVT_KEY1'
          clientSignedCert:
            path: '../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/cert.pem'
    connectionProfile:
      path: '../test-network/organizations/peerOrganizations/org1.example.com/connection-org1.yaml'
      discover: false

  - mspid: Org2MSP
    identities:
      certificates:
        - name: 'User1@org2.example.com'
          clientPrivateKey:
            path: '$PVT_KEY2'
          clientSignedCert:
            path: '../test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts/cert.pem'
    connectionProfile:
      path: '../test-network/organizations/peerOrganizations/org2.example.com/connection-org2.yaml'
      discover: false
EOF

echo "🔥 Running Benchmark (4 rounds — Fail target = 0)..."
echo "   Round 1: IssueCertificate     @ 50 TPS / 30s"
echo "   Round 2: VerifyCertificate    @ 50 TPS / 30s"
echo "   Round 3: QueryAllCertificates @ 20 TPS / 30s"
echo "   Round 4: RevokeCertificate    @ 50 TPS / 30s"

npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test

echo -e "${GREEN}✅ Finished. Report at caliper-workspace/report.html${NC}"
