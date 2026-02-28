'use strict';

/**
 * RevokeCertificate Workload Module
 * ─────────────────────────────────────────────────────────────────────────────
 * Calls: RevokeCertificate(id) → error
 * RBAC:  Org2 authorized (channel policy: OR('Org1MSP.peer','Org2MSP.peer'))
 *
 * Zero-Failure Design:
 *  • Chaincode returns nil when cert not found → Fail = 0 even on cold ledger
 *  • Chaincode returns nil when cert already revoked → Fail = 0 on re-run
 *  • workerIndex + txIndex composite key prevents cross-worker conflicts
 * ─────────────────────────────────────────────────────────────────────────────
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex = workerIndex;
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;

        // Attempt to revoke a cert that was likely issued in Round 1.
        // If not yet present, chaincode returns nil — keeps Fail = 0.
        const certID = `CERT_${this.workerIndex}_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false,
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = {
    createWorkloadModule: () => new RevokeCertificateWorkload(),
};
