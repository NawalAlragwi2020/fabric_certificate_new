'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    /**
    * تهيئة البيانات قبل بدء الاختبار
    */
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, caliperEngine, adapter, blockchainConfig) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, caliperEngine, adapter, blockchainConfig);
    }

    /**
    * إرسال معاملات الإلغاء
    */
    async submitTransaction() {
        this.txIndex++;
        
        // توليد المعرف ليتطابق مع الشهادات التي تم إصدارها (مثلاً Cert_0_1)
        const certificateId = `Cert_${this.workerIndex}_${this.txIndex}`;
        const revocationReason = 'Incorrect Data or Degree Revocation';

        const request = {
            contractId: 'diploma',
            contractFunction: 'RevokeCertificate', // يجب أن يطابق الاسم في ملف الـ Go
            invokerIdentity: 'User1',
            // التأكيد: هنا نرسل وسيطين (id و reason) كما تطلب دالة الـ Go
            contractArguments: [certificateId, revocationReason],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new RevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;