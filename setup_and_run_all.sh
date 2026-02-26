#!/bin/bash
set -e

# تشغيل سكربت إصلاح الصلاحيات
if [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ "${FIX_PERMISSIONS:-}" = "true" ]; then
    if [ -x "./scripts/fix-permissions.sh" ]; then
        echo "🔐 Running scripts/fix-permissions.sh..."
        ./scripts/fix-permissions.sh || true
    fi
fi

# 1. مسح الحاويات والشبكات القديمة
docker rm -f $(docker ps -aq) || true
docker volume prune -f

# 2. Deep Clean لصور العقد الذكي القديمة لضمان تشغيل كود new_branch
echo -e "\n🧹 Performing deep-clean for Docker images starting with dev-*..."
DEV_IMAGE_IDS=$(docker images --format '{{.Repository}} {{.ID}}' | awk '$1 ~ /^(dev-|dev-peer)/ {print $2}' || true)
if [ -n "$DEV_IMAGE_IDS" ]; then
    docker rmi -f $DEV_IMAGE_IDS || true
fi

# 3. مسح التقارير والـ Workspace القديم
rm -f caliper-workspace/report.html
cd caliper-workspace && rm -rf networks/networkConfig.yaml && cd ..

# تعريف الألوان
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting Full Project Setup (Fabric + Caliper)...${NC}"

# 4. تشغيل الشبكة مع CouchDB
cd test-network
./network.sh down
./network.sh up createChannel -c mychannel -ca -s couchdb

# ✅ إضافة وقت انتظار كافٍ لاستقرار CouchDB (مهم جداً لأطروحة الدكتوراه)
echo "⏳ Waiting 30 seconds for CouchDB and Peers to stabilize..."
sleep 30
cd ..

# 5. نشر العقد الذكي بسياسة الـ OR (لحل مشكلة فشل الحذف)
echo "📜 Deploying Smart Contract with OR Policy..."
cd test-network
./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go -ccep "OR('Org1MSP.peer','Org2MSP.peer')"
cd ..

# 6. إعداد Caliper
cd caliper-workspace
if [ ! -d "node_modules" ]; then
    npm install
    npx caliper bind --caliper-bind-sut fabric:2.2
fi

echo "🔑 Detecting Private Keys..."
KEY_DIR1="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY1=$(ls $KEY_DIR1/*_sk)
KEY_DIR2="../test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
PVT_KEY2=$(ls $KEY_DIR2/*_sk)

# ✅ إنشاء ملف networkConfig.yaml بتنسيق سليم (تم تصحيح المسافات هنا)
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
      discover: true

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
      discover: true
EOF

echo "🔥 Running Benchmark..."
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test

echo -e "${GREEN}✅ Finished. Report at caliper-workspace/report.html${NC}"
