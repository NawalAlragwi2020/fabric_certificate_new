#!/bin/bash
set -e

# تعريف الألوان للنصوص
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting SecureBlockCert Project Setup (Optimized Benchmark Mode)...${NC}"
echo "=================================================="

# 1. التأكد من وجود الأدوات وإعداد المسارات
echo -e "${GREEN}📦 Step 1: Checking Fabric Binaries...${NC}"
export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

if [ ! -d "bin" ]; then
    echo "⬇️ Downloading Fabric tools..."
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
fi

# 2. إعادة تشغيل الشبكة وتنظيف الحاويات القديمة
echo -e "${GREEN}🌐 Step 2: Restarting Fabric Network...${NC}"
cd test-network
./network.sh down
./network.sh up createChannel -c mychannel -ca
cd ..

# 3. تجهيز ونشر العقد الذكي (مع إصلاح مشاكل Go)
echo -e "${GREEN}📜 Step 3: Preparing & Deploying Secure Chaincode...${NC}"

cd asset-transfer-basic/chaincode-go
# تنظيف الموديلات والتأكد من تحميل كافة المكتبات (بما فيها التشفير)
go mod tidy
go mod vendor 
cd ../../

# نشر العقد الذكي
cd test-network
./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go
cd ..

# 4. إعداد وتشغيل Caliper
echo -e "${GREEN}⚡ Step 4: Configuring & Running Caliper...${NC}"
cd caliper-workspace

# تثبيت المكتبات إذا لم تكن موجودة
if [ ! -d "node_modules" ]; then
    echo "📦 Installing Caliper dependencies..."
    npm install
    npx caliper bind --caliper-bind-sut fabric:2.4
fi

# البحث عن المفتاح الخاص (خطوة حاسمة لنجاح الاتصال)
echo "🔑 Detecting Private Key..."
KEY_DIR="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY=$(ls $KEY_DIR/*_sk | head -n 1)

if [ -z "$PVT_KEY" ]; then
    echo -e "${RED}❌ Error: Private key not found!${NC}"
    exit 1
fi
echo "✅ Found Key: $(basename $PVT_KEY)"

# توليد ملف إعدادات الشبكة (بناءً على المسار الفعلي للمفتاح)
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
        - name: 'User1'
          clientPrivateKey:
            path: '$PVT_KEY'
          clientSignedCert:
            path: '../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/cert.pem'
    connectionProfile:
      path: '../test-network/organizations/peerOrganizations/org1.example.com/connection-org1.yaml'
      discover: true
EOF

# التأكد من وجود ملف الـ Benchmark
if [ ! -f "benchmarks/benchConfig.yaml" ]; then
    echo -e "${RED}❌ Error: benchmarks/benchConfig.yaml not found!${NC}"
    exit 1
fi

# تشغيل الاختبار
echo "🔥 Running Benchmarks..."
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}🎉 Benchmark Finished Successfully!${NC}"
echo -e "${GREEN}📄 Check report: caliper-workspace/report.html${NC}"
