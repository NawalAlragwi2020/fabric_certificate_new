'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto'); // مكتبة التشفير لمحاكاة SHA-3

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0; 
    }

    /**
    * تهيئة المتغيرات لكل عامل (Worker)
    */
    async initializeWorkloadModule(workerIndex, totalWorkers, numberofIndices, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, numberofIndices, sutAdapter, sutContext);
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        
        // --- المنطق الآمن لضمان وجود الشهادة ---
        // نحن نستخدم نفس النمط المستخدم في ملف issueDiplomaBatch.js
        // العداد (this.txIndex) هنا سيبدأ من 1، 2، 3... 
        // بما أن جولة الإصدار استمرت 30 ثانية وجولة الإلغاء 20 ثانية فقط،
        // فنحن نضمن حسابياً أن هذه المعرفات موجودة في الـ Ledger.
        const rawID = `Cert_${this.workerIndex}_${this.txIndex}`;

        // تشفير المعرف باستخدام SHA-3 (مطابق تماماً لما يفعله الـ Chaincode في Go)
        const certID = crypto.createHash('sha3-256').update(rawID).digest('hex');

        const requestSettings = {
            contractId: 'diploma', 
            contractFunction: 'RevokeCertificate', 
            contractArguments: [certID, 'Administrative decision for revocation'],
            readOnly: false
        };

        try {
            await this.sutAdapter.sendRequests(requestSettings);
        } catch (error) {
            // طباعة الخطأ في حال فشل الاتصال، لكن المنطق الرياضي يضمن وجود الـ ID
            console.error(`Worker ${this.workerIndex} failed to revoke certificate ${certID}: ${error.message}`);
        }
    }
}

function createWorkloadModule() {
    return new RevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
