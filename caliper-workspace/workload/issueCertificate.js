'use strict';

/**
 * IssueCertificate Workload Module
 * ─────────────────────────────────────────────────────────────────────────────
 * Calls: IssueCertificate(id, studentName, degree, issuer, issueDate, certHash)
 * RBAC:  Org1MSP only
 *
 * Zero-Failure Design:
 *  • Each worker uses a composite key (workerIndex + txIndex) → no collisions
 *  • Chaincode is idempotent: duplicate ID returns nil (not error)
 *  • SHA-256 hash is pre-computed to match VerifyCertificate expectations
 * ─────────────────────────────────────────────────────────────────────────────
 */

'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.workerIndex = 0;
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
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = new Date().toISOString().split('T')[0];   // YYYY-MM-DD
        // SHA-256 matches what VerifyCertificate will check
        const certHash    = crypto
            .createHash('sha256')
            .update(certID + studentName)
            .digest('hex');

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',
            // Argument order MUST match Go signature:
            // IssueCertificate(ctx, id, studentName, degree, issuer, issueDate, certHash)
            contractArguments: [certID, studentName, degree, issuer, issueDate, certHash],
            readOnly:          false,
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = {
    createWorkloadModule: () => new IssueCertificateWorkload(),
};
