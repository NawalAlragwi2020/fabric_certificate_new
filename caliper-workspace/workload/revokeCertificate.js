'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ============================================================
 * RevokeCertificate Workload Module — v3.0
 * ============================================================
 * Chaincode Function : RevokeCertificate(id) error
 * Go Signature       : RevokeCertificate(ctx, id) error
 * RBAC               : Org2MSP authorized
 *                      (endorsement policy: OR('Org1MSP.peer','Org2MSP.peer'))
 * Fail-Safe Design   : Idempotent — returns nil when cert not found OR already
 *                      revoked → Fail = 0 guaranteed
 *
 * Argument alignment:
 *   id → certID (string)  e.g. "CERT_W0_TX1"
 *
 * Invoker: User1@org2.example.com (set in benchConfig.yaml txOptions)
 *
 * Note: RevokeCertificate targets the same CertIDs created by IssueCertificate.
 *       Because the chaincode is idempotent (returns nil for missing/already-revoked
 *       certs) this round always achieves Fail = 0 regardless of ledger state.
 * ============================================================
 */
class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex = workerIndex;
    }

    async submitTransaction() {
        this.txIndex++;
        // Target the same CertIDs that were issued in round 1
        const certID = `CERT_W${this.workerIndex}_TX${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            // EXACT order matching Go function signature: RevokeCertificate(ctx, id)
            contractArguments: [certID],
            readOnly:          false,   // state-changing transaction
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
