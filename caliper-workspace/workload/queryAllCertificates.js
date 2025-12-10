'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async submitTransaction() {
        const request = {
            contractId: 'basic',
            contractFunction: 'GetAllAssets',
            contractArguments: [],
            readOnly: true
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new QueryAllWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;