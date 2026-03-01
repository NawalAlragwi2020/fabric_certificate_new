'use strict';

/**
 * Revoke Certificate Workload — Round 4
 * =======================================
 * Invokes: RevokeCertificate(certID)
 *
 * Zero-Failure Design:
 *   - Chaincode is idempotent: returns nil for missing or already-revoked certs
 *   - Uses certIDs from Round 1 pattern (may or may not exist — both are OK)
 *   - Org2MSP RBAC: invokerIdentity = User1@org2.example.com
 *   - postIterationWaitTime: 3000ms to allow ledger to settle between iterations
 *
 * Org2MSP RBAC: invokerIdentity = User1@org2.example.com
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {

    constructor() {
        super();
        this.txIndex = 0;
    }

    /**
     * Called once before the benchmark round starts.
     */
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex = workerIndex;
        this.contractId = roundArguments.contractId || 'basic';
        this.txIndex = 0;

        // Pre-generate a list of certIDs to revoke — mix of existing and non-existing
        // Non-existing are fine because chaincode returns nil (idempotent)
        this.certIDPool = [];
        for (let i = 1; i <= 500; i++) {
            // Reference certs from Round 1 (issued by various workers)
            this.certIDPool.push(`CERT-W${i % 4}-TX${i}-REVOKE`);
        }
    }

    /**
     * Called for each transaction. Submits RevokeCertificate.
     *
     * Uses Org2 identity (defined in networkConfig.yaml under Org2MSP).
     * Chaincode RBAC allows Org2MSP to revoke.
     */
    async submitTransaction() {
        this.txIndex++;

        // Cycle through the certID pool — idempotent design handles re-revocations
        const certID = this.certIDPool[this.txIndex % this.certIDPool.length];

        const request = {
            contractId: this.contractId,
            contractFunction: 'RevokeCertificate',
            contractArguments: [certID],
            invokerIdentity: 'User1@org2.example.com',   // ← Org2 identity
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }

    /**
     * Called once after the benchmark round ends.
     */
    async cleanupWorkloadModule() {
        // Nothing to clean up
    }
}

/**
 * Factory function — required by Caliper
 */
function createWorkloadModule() {
    return new RevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
