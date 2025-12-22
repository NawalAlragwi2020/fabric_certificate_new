'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllDiplomasWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async submitTransaction() {
        const request = {
            contractId: 'diploma',
            contractFunction: 'GetAllDiplomas', // الوظيفة المحدثة في الـ Chaincode
            contractArguments: [],
            readOnly: true
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new QueryAllDiplomasWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;