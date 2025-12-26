#!/bin/bash
set -e

# 1. تنظيف أي إعدادات سابقة للشبكة
sudo tc qdisc del dev eth0 root || true
echo "🚀 جاري بدء عملية الإصلاح والتجهيز الأمنية..."

# 2. تحميل أدوات Hyperledger Fabric
if [ ! -d "bin" ]; then
    echo "⬇ جاري تحميل الأدوات (Binaries)..."
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
    echo "✅ الأدوات موجودة مسبقاً."
fi

# 3. إعداد المسارات الأساسية
export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# 4. إعادة تشغيل الشبكة من الصفر
cd test-network
./network.sh down
./network.sh up createChannel -c mychannel -ca
cd ..

# ============================================================
# خطوة التحديث الأمني (SHA-3) - تُضاف هنا قبل النشر
# ============================================================
echo "🛡️ جاري تجهيز المكتبات الأمنية (SHA-3/Keccak)..."
cd asset-transfer-basic/chaincode-go
go get golang.org/x/crypto/sha3
go mod tidy
cd ../..
# ============================================================

# 5. نشر العقد المطور (مع دعم Batching + SHA-3)
cd test-network
./network.sh deployCC \
  -ccn diploma \
  -ccv 3.0 \
  -ccs 2 \
  -ccp ../asset-transfer-basic/chaincode-go \
  -ccl go
cd ..

# 6. محاكاة تأخير ورقة 2025 (200ms)
echo "🌐 Simulating Network Delay (200ms) on eth0..."
sudo tc qdisc add dev eth0 root netem delay 200ms

# 7. إعداد Caliper وتشغيل الاختبار
cd caliper-workspace
npm install
mkdir -p networks

# البحث عن المفتاح الخاص
KEY_DIR="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY=$(ls $KEY_DIR/*_sk)

# توليد ملف الإعدادات
cat << EOF > networks/networkConfig.yaml
name: Caliper-Fabric
version: "2.0.0"
caliper:
  blockchain: fabric
channels:
  - channelName: mychannel
    contracts:
      - id: diploma
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

# 8. تشغيل الاختبار النهائي
echo "🔥 Running Benchmarks (SHA-3 & Batching)..."
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test
