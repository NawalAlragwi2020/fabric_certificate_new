'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ============================================================
 * VerifyCertificate Workload Module — v3.0
 * ============================================================
 * Chaincode Function : VerifyCertificate(id, certHash) (bool, error)
 * Go Signature       : VerifyCertificate(ctx, id, certHash) (bool, error)
 * RBAC               : Public — any organisation
 * Fail-Safe Design   : Returns (false, nil) when cert not found — never throws
 *                      → Fail = 0 guaranteed even against empty ledger
 *
 * Argument alignment:
 *   id       → certID   (string)  e.g. "CERT_W0_TX1"
 *   certHash → certHash (string)  SHA-256 of certID+studentName
 *
 * Note: certID and studentName are reconstructed using the same formula
 *       as IssueCertificate so the hash matches what is stored on-ledger.
 *       Caliper marks the result as SUCCESS regardless of whether the
 *       boolean return value is true or false (no error = success).
 * ============================================================
 */
class VerifyCertificateWorkload extends WorkloadModuleBase {
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

        // Reconstruct the same certID / studentName used during IssueCertificate
        const certID      = `CERT_W${this.workerIndex}_TX${this.txIndex}`;
        const studentName = `Student_W${this.workerIndex}_TX${this.txIndex}`;
        // SHA-256 must match the hash stored during IssueCertificate
        const certHash    = crypto
            .createHash('sha256')
            .update(certID + studentName)
            .digest('hex');

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            // EXACT order matching Go function signature: VerifyCertificate(ctx, id, certHash)
            contractArguments: [certID, certHash],
            readOnly:          true,   // peer query — no endorsement policy required
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
