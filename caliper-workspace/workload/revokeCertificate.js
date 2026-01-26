'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto'); // مكتبة التشفير لمحاكاة SHA-3

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0; // تتبع عدد المعاملات
    }

    async submitTransaction() {
        this.txIndex++;
        
        // 1. توليد المعرف الخام (نفس النمط المستخدم في الإصدار)
        // ملاحظة: تأكد أن هذا النمط يطابق تماماً ما استخدمته في issueDiplomaBatch.js
        const rawID = `Cert_${this.workerIndex}_${this.txIndex}`;

        // 2. تشفير المعرف باستخدام SHA-3 ليتطابق مع ما هو مخزن في Ledger
        const certID = crypto.createHash('sha3-256').update(rawID).digest('hex');

        const requestSettings = {
            contractId: 'diploma', // تأكد أن هذا هو الاسم المستخدم عند تثبيت الـ Chaincode
            contractFunction: 'RevokeCertificate', // تأكد أن الاسم يطابق الدالة في smartcontract.go
            contractArguments: [certID, 'Administrative decision for revocation'],
            readOnly: false
        };

        try {
            await this.sutAdapter.sendRequests(requestSettings);
        } catch (error) {
            console.error(`Failed to revoke certificate ${certID}: ${error}`);
        }
    }
}

function createWorkloadModule() {
    return new RevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
