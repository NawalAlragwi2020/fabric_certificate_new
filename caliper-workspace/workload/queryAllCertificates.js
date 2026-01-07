'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async submitTransaction() {
        const request = {
            contractId: 'basic',
            // تم تغيير اسم الدالة لتطابق ما كتبناه في Chaincode
            contractFunction: 'QueryAllCertificates', 
            contractArguments: [],
            // بما أن العملية قراءة فقط، نتركها true لتحسين الأداء
            readOnly: true
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new QueryAllCertificatesWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
