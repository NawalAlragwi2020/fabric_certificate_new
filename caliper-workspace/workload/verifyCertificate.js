'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        // نبحث عن نفس الشهادة التي أصدرناها في الخطوة السابقة
        const certID = `cert_${this.workerIndex}_${this.txIndex}`;

        const request = {
            contractId: 'basic',
            contractFunction: 'ReadAsset',
            contractArguments: [certID],
            readOnly: true
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new VerifyCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;