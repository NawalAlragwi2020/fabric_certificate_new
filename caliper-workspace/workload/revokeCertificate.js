'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, numberofIndices, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, numberofIndices, sutAdapter, sutContext);
    }

    async submitTransaction() {
        // 1. تحديد النمط: يجب أن يكون مطابقاً تماماً لما تم استخدامه في issueDiplomaBatch.js
        // نحن نفترض هنا أن الإصدار استخدم النمط: "Cert_WorkerIndex_TransactionIndex"
        
        // توليد رقم عشوائي ضمن نطاق المعاملات التي تمت في مرحلة الإصدار (مثلاً أول 100 معاملة)
        const randomTxIndex = Math.floor(Math.random() * 100); 
        const certID = `Cert_${this.workerIndex}_${randomTxIndex}`;

        const requestSettings = {
            contractId: 'diploma',
            contractFunction: 'RevokeCertificate',
            contractArguments: [certID, 'Administrative decision for revocation'],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(requestSettings);
    }
}

function createWorkloadModule() {
    return new RevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;