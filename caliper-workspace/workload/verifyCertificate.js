'use strict';

/**
 * VerifyCertificate Workload Module
 * ─────────────────────────────────────────────────────────────────────────────
 * Calls: VerifyCertificate(id, certHash) → (bool, error)
 * RBAC:  Public (any org)
 *
 * Zero-Failure Design:
 *  • readOnly: true  → no ordering required, goes directly to peers
 *  • Chaincode returns false (not error) when cert not found
 *  • Hash is computed identically to IssueCertificate
 * ─────────────────────────────────────────────────────────────────────────────
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class VerifyCertificateWorkload extends WorkloadModuleBase {
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

        const certID      = `CERT_${this.workerIndex}_${this.txIndex}`;
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        // Identical hash as IssueCertificate — will return true for issued certs
        const certHash    = crypto
            .createHash('sha256')
            .update(certID + studentName)
            .digest('hex');

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true,     // ← read-only: fast peer query, no order
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = {
    createWorkloadModule: () => new VerifyCertificateWorkload(),
};
