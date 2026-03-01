'use strict';

/**
 * QueryAllCertificates Workload Module
 * ─────────────────────────────────────────────────────────────────────────────
 * Calls: QueryAllCertificates() → []*Certificate
 * RBAC:  Public (any org)
 *
 * Zero-Failure Design:
 *  • readOnly: true  → fast peer query, bypasses ordering service
 *  • Chaincode returns empty slice (not nil/error) on empty ledger
 *  • No arguments needed → no argument mismatch errors
 * ─────────────────────────────────────────────────────────────────────────────
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        const request = {
            contractId:        'basic',
            contractFunction:  'QueryAllCertificates',
            contractArguments: [],       // ← no args: Go signature takes only ctx
            readOnly:          true,
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = {
    createWorkloadModule: () => new QueryAllCertificatesWorkload(),
};
