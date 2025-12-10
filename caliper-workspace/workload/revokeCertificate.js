'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        // نحذف نفس الشهادة التي تم إنشاؤها
        const certID = `cert_${this.workerIndex}_${this.txIndex}`;

        const request = {
            contractId: 'basic',
            contractFunction: 'DeleteAsset',
            contractArguments: [certID],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new RevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;