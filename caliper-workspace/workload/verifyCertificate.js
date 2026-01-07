'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        
        // يجب أن يتطابق نمط المعرف مع ما تم إصداره في ملف issueCertificate.js
        const certID = `CERT_${this.workerIndex}_${this.txIndex}`;
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        
        // إعادة توليد نفس الـ Hash الذي استخدمناه عند الإصدار لمحاكاة عملية تحقق ناجحة
        const certHash = Buffer.from(certID + studentName).toString('hex');

        const request = {
            contractId: 'basic',
            // استدعاء دالة التحقق الذكية التي كتبناها في Go
            contractFunction: 'VerifyCertificate', 
            contractArguments: [
                certID, 
                certHash
            ],
            readOnly: true // التحقق هو عملية قراءة ولا يغير في حالة البلوكشين
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new VerifyCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
