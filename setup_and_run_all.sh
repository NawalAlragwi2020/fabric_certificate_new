#!/bin/bash
set -e

# 1. تنظيف أي إعدادات سابقة للشبكة
sudo tc qdisc del dev eth0 root || true

echo "🚀 Starting Full Project Setup (Fabric + Caliper)..."

# 2. إعداد المسارات الأساسية
export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# 3. إعادة تشغيل الشبكة من الصفر (لضمان عمل الـ Sequence 1)
cd test-network
./network.sh down
./network.sh up createChannel -c mychannel -ca
cd ..

# 4. نشر العقد المطور (مع دعم Batching)
cd test-network
./network.sh deployCC \
  -ccn diploma \
  -ccv 2.0 \
  -ccs 1 \
  -ccp ../asset-transfer-basic/chaincode-go \
  -ccl go
cd ..

# 5. محاكاة تأخير ورقة 2025 على الواجهة الصحيحة (eth0)
echo "🌐 Simulating Network Delay (200ms) on eth0..."
sudo tc qdisc add dev eth0 root netem delay 200ms

# 6. إعداد Caliper وتشغيل الاختبار
cd caliper-workspace
npm install   # حل مشكلة npm (الصورة 6)
mkdir -p networks # حل مشكلة الملف المفقود (الصورة 5)

# البحث عن المفتاح الخاص
KEY_DIR="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY=$(ls $KEY_DIR/*_sk)

# توليد ملف الإعدادات (مع تصحيح الـ ID إلى diploma)
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

# 7. تشغيل الاختبار النهائي
echo "🔥 Running Benchmarks..."
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test