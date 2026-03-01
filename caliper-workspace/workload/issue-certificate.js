'use strict';

/**
 * Issue Certificate Workload — Round 1
 * =====================================
 * Invokes: IssueCertificate(certID, studentName, degree, issuer, issueDate, certHash)
 *
 * Zero-Failure Design:
 *   - Uses unique certID per worker+tx to avoid duplicates causing real errors
 *   - Chaincode is idempotent (duplicate returns nil) as backup safety
 *   - SHA-256 hash provided as hex string matching Go chaincode expectation
 *
 * Org1MSP RBAC: invokerIdentity = User1@org1.example.com
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class IssueCertificateWorkload extends WorkloadModuleBase {

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
    }

    /**
     * Called for each transaction. Submits IssueCertificate.
     */
    async submitTransaction() {
        this.txIndex++;

        // Unique certID per worker per transaction — prevents duplicate conflicts
        const certID = `CERT-W${this.workerIndex}-TX${this.txIndex}-${Date.now()}`;

        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        const degree = 'Bachelor of Science in Computer Science';
        const issuer = 'BCMS University';
        const issueDate = '2026-01-01';

        // Compute SHA-256 hash of certID+studentName for authenticity
        const certHash = crypto
            .createHash('sha256')
            .update(`${certID}:${studentName}:${degree}`)
            .digest('hex');

        const request = {
            contractId: this.contractId,
            contractFunction: 'IssueCertificate',
            contractArguments: [certID, studentName, degree, issuer, issueDate, certHash],
            invokerIdentity: 'User1@org1.example.com',
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
    return new IssueCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
