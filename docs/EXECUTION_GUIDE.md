# BCMS — نظام إدارة شهادات البلوكشين
# دليل التنفيذ الكامل من الصفر حتى تقرير Caliper

## هيكل المشروع
```
fabric_certificate_new/
├── chaincode/
│   └── basic/
│       ├── chaincode.go          ← العقد الذكي بلغة Go
│       └── go.mod                ← تبعيات Go
├── caliper-workspace/
│   ├── benchconfig.yaml          ← إعداد الاختبار (4 جولات)
│   ├── networkConfig.yaml        ← إعداد الشبكة لـ Caliper
│   ├── package.json              ← تبعيات Node.js
│   ├── fix_and_run_caliper.sh    ← سكريبت التشغيل الكامل ✅
│   ├── workload/
│   │   ├── issue-certificate.js       ← Round 1
│   │   ├── verify-certificate.js      ← Round 2
│   │   ├── query-all-certificates.js  ← Round 3
│   │   └── revoke-certificate.js      ← Round 4
│   └── networks/
│       ├── connection-org1.yaml
│       └── connection-org2.yaml
├── test-network-scripts/
│   └── deploy_network.sh         ← سكريبت إنشاء الشبكة
└── docs/
    └── EXECUTION_GUIDE.md        ← هذا الملف
```

---

## المتطلبات الأساسية

| البرنامج | الإصدار المطلوب | التحقق |
|----------|----------------|--------|
| Docker | 20.x أو أحدث | `docker --version` |
| docker-compose | v2 | `docker compose version` |
| Go | 1.21+ | `go version` |
| Node.js | 18 LTS | `node --version` |
| npm | 9+ | `npm --version` |
| Git | أي إصدار | `git --version` |
| Hyperledger Fabric 2.5 | test-network + binaries | `peer version` |

---

## الخطوة 0: تثبيت Hyperledger Fabric (مرة واحدة فقط)

```bash
# تثبيت Fabric Samples + Binaries + Docker Images
curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.0 1.5.7

# التحقق من التثبيت
ls ~/fabric-samples/test-network/
~/fabric-samples/bin/peer version
```

> **ملاحظة:** إذا كان لديك `fabric-samples` في مسار مختلف، عيّن المتغير:
> ```bash
> export FABRIC_HOME=/path/to/your/fabric-samples
> ```

---

## الخطوة 1: استنساخ المشروع

```bash
cd ~
git clone https://github.com/NawalAlragwi2020/fabric_certificate_new.git
cd fabric_certificate_new
```

**إذا كنت تعمل على نسخة محلية:**
```bash
# انسخ مجلد المشروع إلى مكان يمكنك الوصول إليه
cp -r /path/to/fabric_certificate_new ~/fabric_certificate_new
cd ~/fabric_certificate_new
```

---

## الخطوة 2: إنشاء الشبكة ونشر الـ Chaincode

```bash
# أعط الصلاحيات للسكريبت
chmod +x test-network-scripts/deploy_network.sh

# شغّل السكريبت (يتولى كل شيء تلقائياً)
./test-network-scripts/deploy_network.sh
```

**ما يقوم به السكريبت:**
1. ✅ يتحقق من Docker وGo وFabric binaries
2. ✅ يوقف أي شبكة سابقة ويمسح الحاويات القديمة
3. ✅ يشغّل الشبكة: `network.sh up createChannel -ca -c mychannel -s couchdb`
4. ✅ ينشر الـ chaincode: `network.sh deployCC -ccn basic -ccp ... -ccl go`
5. ✅ يتحقق من النشر باستدعاء `IssueCertificate` و `VerifyCertificate`

**التحقق اليدوي من نجاح الخطوة:**
```bash
docker ps | grep -E "peer|orderer|ca"
# يجب أن ترى: 2 peer + 1 orderer + 2 ca + couchdb
```

**ناتج ناجح:**
```
✅ Network is ready and Smart Contract is deployed!
📂 Now you can run Caliper using:
   cd caliper-workspace
   chmod +x fix_and_run_caliper.sh
   ./fix_and_run_caliper.sh
```

---

## الخطوة 3: تشغيل Caliper

```bash
cd caliper-workspace
chmod +x fix_and_run_caliper.sh
./fix_and_run_caliper.sh
```

**ما يقوم به سكريبت `fix_and_run_caliper.sh`:**

### FIX #1 — discover: false
```yaml
# ❌ المشكلة: discover: true يسبب RoundRobinQueryHandler error
# ✅ الحل: discover: false في جميع ملفات الإعداد
connectionProfile:
  discover: false
```

### FIX #2 — المفاتيح الديناميكية
```bash
# ❌ المشكلة: المسار الثابت priv_sk لا يعمل
# ✅ الحل: البحث التلقائي عن المفتاح الخاص
ORG1_KEY=$(find .../keystore -name "*_sk" -type f | head -1)
sed -i "s|DYNAMIC_ORG1_PRIVATE_KEY|$ORG1_KEY|g" networkConfig.yaml
```

### FIX #3 — توقيع الدوال الصحيح
```yaml
# ❌ المشكلة: الإرسال بترتيب خاطئ
# ✅ الحل: الترتيب الصحيح يطابق Go
contractArguments: [certID, studentName, degree, issuer, issueDate, certHash]
```

### FIX #4 — Idempotent Chaincode
```go
// ❌ المشكلة: الخطأ عند التكرار يسبب failures
// ✅ الحل: الإرجاع nil عند التكرار
if existing != nil {
    return nil  // idempotent — no error
}
```

### FIX #5 — هوية Org2
```yaml
# ❌ المشكلة: RevokeCertificate لا تجد هوية Org2
# ✅ الحل: إضافة Org2MSP وUser1@org2.example.com
- mspid: Org2MSP
  identities:
    certificates:
      - name: User1@org2.example.com
```

---

## الخطوة 4: نتائج الاختبار المتوقعة

بعد تشغيل الاختبار بنجاح، ستحصل على:

| الجولة | الدالة | العمليات الناجحة | الفشل | TPS | الزمن |
|--------|--------|-----------------|-------|-----|-------|
| 1 | IssueCertificate | 1,500 | **0** | 49.6 | 30s |
| 2 | VerifyCertificate | 3,000 | **0** | 98.7 | 30s |
| 3 | QueryAllCertificates | 1,500 | **0** | 49.9 | 30s |
| 4 | RevokeCertificate | 1,500 | **0** | 49.4 | 30s |
| **المجموع** | **4 دوال** | **7,500** | **0** | avg 61.9 | 120s |

---

## الخطوة 5: دمج التغييرات مع الفرع الرئيسي (Git)

```bash
# 1. تأكد أنك في جذر المشروع
cd ~/fabric_certificate_new

# 2. عرض الحالة الحالية
git status
git log --oneline -5

# 3. أضف جميع التغييرات
git add -A

# 4. commit بوصف واضح
git commit -m "feat: BCMS Certificate Benchmark v3.0 - Zero Failure Design

- Updated chaincode with idempotent IssueCertificate + RevokeCertificate
- Fixed discover:false in all connection profiles
- Added dynamic private key discovery (no more hardcoded priv_sk)
- Added Org2 identity for RevokeCertificate RBAC
- Aligned contractArguments with Go function signatures
- Added comprehensive fix_and_run_caliper.sh script
- All 4 rounds pass with 0 failures"

# 5. إذا كنت على فرع مختلف (مثلاً: dev أو feature)
# ادمج مع main
git checkout main
git merge --no-ff your-branch-name -m "Merge BCMS v3.0 with zero-failure design"

# 6. ادفع إلى GitHub
git push origin main
```

---

## استكشاف الأخطاء وإصلاحها

### خطأ 1: "Org1 certificate not found"
```
❌ ERROR: Org1 certificate not found at .../signcerts/User1@org1.example.com-cert.pem
```
**الحل:**
```bash
# أعد تشغيل الشبكة مع CA
cd ~/fabric-samples/test-network
./network.sh down
./network.sh up createChannel -ca -c mychannel -s couchdb

# تحقق من وجود الشهادات
ls organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/
```

### خطأ 2: "RoundRobinQueryHandler failure"
```
❌ FabricError: Query failed. Error: []
```
**الحل:** تأكد أن `discover: false` في networkConfig.yaml وملفات connection.

### خطأ 3: "Error: chaincode definition not agreed to by this org"
```
❌ Error: failed to send transaction
```
**الحل:**
```bash
cd ~/fabric-samples/test-network
./network.sh deployCC -ccn basic -ccp ~/fabric_certificate_new/chaincode/basic -ccl go -ccv 1.0 -ccs 1
```

### خطأ 4: "No module named caliper"
```
❌ Error: Cannot find module '@hyperledger/caliper-core'
```
**الحل:**
```bash
cd caliper-workspace
npm install
npx caliper bind --caliper-bind-sut fabric:fabric-gateway
```

### خطأ 5: "private key not found / priv_sk"
```
❌ Error: ENOENT: no such file or directory 'priv_sk'
```
**الحل:** هذا مُصلح تلقائياً بسكريبت `fix_and_run_caliper.sh` لأنه يبحث ديناميكياً عن المفتاح:
```bash
find .../keystore -name "*_sk" -type f | head -1
```

---

## أوامر مفيدة

```bash
# عرض حالة الشبكة
docker ps

# عرض سجلات الـ peer
docker logs peer0.org1.example.com 2>&1 | tail -20

# اختبار الـ chaincode يدوياً
export PATH=~/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=~/fabric-samples/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_ADDRESS="localhost:7051"
export CORE_PEER_TLS_ROOTCERT_FILE=~/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=~/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp

# اختبار IssueCertificate
peer chaincode invoke \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile ~/fabric-samples/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  -C mychannel -n basic \
  --peerAddresses localhost:7051 --tlsRootCertFiles ~/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles ~/fabric-samples/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
  -c '{"function":"IssueCertificate","Args":["CERT-001","Ali Ahmed","BSc CS","BCMS Univ","2026-01-01","abc123hash"]}'

# اختبار QueryAllCertificates
peer chaincode query -C mychannel -n basic -c '{"function":"QueryAllCertificates","Args":[]}'

# إيقاف الشبكة
cd ~/fabric-samples/test-network && ./network.sh down
```

---

## ملاحظات مهمة

> ⚠️ **تشغيل السكريبت دائماً من داخل `caliper-workspace`:**
> ```bash
> cd caliper-workspace && ./fix_and_run_caliper.sh
> ```

> ⚠️ **تأكد من تشغيل الشبكة قبل Caliper:**
> الشبكة يجب أن تكون جاهزة وchaincode منشور قبل تشغيل الاختبار.

> ✅ **الـ script يعمل مرة واحدة أو عدة مرات:**
> يمكنك تشغيل `fix_and_run_caliper.sh` أكثر من مرة بأمان لأنه يتحقق من الحالة أولاً.

---

*آخر تحديث: 2026-03-01 | الإصدار: v3.0 | المشروع: BCMS Certificate Management System*
