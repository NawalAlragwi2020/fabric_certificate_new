'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        // معرف موحد نستخدمه في جميع المراحل
        const certID = `cert_${this.workerIndex}_${this.txIndex}`;

        const request = {
            contractId: 'basic',
            contractFunction: 'CreateAsset',
            contractArguments: [
                certID,                     // ID
                'Student ' + this.txIndex,  // Name
                95,                         // Grade (INT required)
                'Blockchain 101',           // Course
                2025                        // Year (INT required)
            ],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new IssueCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;