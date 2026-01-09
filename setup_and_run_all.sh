#!/bin/bash
set -e

# تعريف الألوان للنصوص
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting SecureBlockCert Project Setup (Omar Saad Benchmark Mode)...${NC}"
echo "=================================================="

# --------------------------------------------------------
# 1. التأكد من وجود الأدوات
# --------------------------------------------------------
echo -e "${GREEN}📦 Step 1: Checking Fabric Binaries...${NC}"
if [ ! -d "bin" ]; then
    echo "⬇️ Downloading Fabric tools..."
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
    echo "✅ Fabric tools found."
fi

export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# --------------------------------------------------------
# 2. تشغيل الشبكة
# --------------------------------------------------------
echo -e "${GREEN}🌐 Step 2: Restarting Fabric Network...${NC}"
cd test-network
./network.sh down
./network.sh up createChannel -c mychannel -ca
cd ..

# --------------------------------------------------------
# 3. تجهيز ونشر العقد الذكي (مع مكتبات التشفير)
# --------------------------------------------------------
echo -e "${GREEN}📜 Step 3: Preparing & Deploying Secure Chaincode...${NC}"

# تعديل 1: تنفيذ vendor لضمان وجود مكتبات التشفير داخل الحاوية
cd asset-transfer-basic/chaincode-go
go mod tidy
go mod vendor
cd ../../

cd test-network
./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go
cd ..

# --------------------------------------------------------
# 4. إعداد وتشغيل Caliper
# --------------------------------------------------------
echo -e "${GREEN}⚡ Step 4: Configuring & Running Caliper...${NC}"
cd caliper-workspace

# أ) تثبيت المكتبات
if [ ! -d "node_modules" ]; then
    echo "📦 Installing Caliper dependencies..."
    npm install
    # تعديل 2: الربط بنسخة 2.4 لأن Caliper الرسمي لا يدعم 2.5 بشكل كامل بعد ولكنه يعمل معها
    npx caliper bind --caliper-bind-sut fabric:2.4
fi

# ب) البحث عن المفتاح الخاص
echo "🔑 Detecting Private Key..."
KEY_DIR="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY=$(ls $KEY_DIR/*_sk | head -n 1)
echo "✅ Found Key: $(basename $PVT_KEY)"

# ج) إنشاء ملف إعدادات الشبكة
echo "⚙️ Generating network config..."
mkdir -p networks
# تعديل 3: إصلاح تنسيق الـ YAML (إضافة الفراغات والناقص قبل العناصر)
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

# د) تشغيل الاختبار
echo "🔥 Running Benchmarks (Issue & Verify Only)..."
# تعديل 4: دمج الأسطر المكسورة باستخدام الـ backslash \
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}🎉 Benchmark Finished Successfully!${NC}"
echo -e "${GREEN}📄 Report: caliper-workspace/report.html${NC}"
