'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ============================================================
 * IssueCertificate Workload Module — v3.0
 * ============================================================
 * Chaincode Function : IssueCertificate(id, studentName, degree, issuer, issueDate, certHash)
 * Go Signature       : IssueCertificate(ctx, id, studentName, degree, issuer, issueDate, certHash) error
 * RBAC               : Org1MSP only  (enforced inside chaincode)
 * Fail-Safe Design   : Idempotent — duplicate CertID returns nil → Fail = 0 guaranteed
 *
 * Argument alignment with Go struct fields:
 *   ID          → certID      (string)  e.g. "CERT_0_1"
 *   StudentName → studentName (string)  e.g. "Student_0_1"
 *   Degree      → degree      (string)  e.g. "Bachelor of Computer Science"
 *   Issuer      → issuer      (string)  e.g. "Digital University"
 *   IssueDate   → issueDate   (string)  e.g. "2026-03-01"
 *   CertHash    → certHash    (string)  SHA-256 of certID+studentName
 * ============================================================
 */
class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    /**
     * Called once per worker before rounds begin.
     * Captures workerIndex so we can build collision-free unique IDs.
     */
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex = workerIndex;
    }

    /**
     * submitTransaction() is called once per TPS tick by Caliper.
     * Generates a unique CertID per (worker, tick) pair to avoid duplicate-key
     * collisions across concurrent workers while still exercising the idempotency
     * path on retry.
     */
    async submitTransaction() {
        this.txIndex++;

        // Unique ID per worker + transaction — no collisions, no duplicates
        const certID      = `CERT_W${this.workerIndex}_TX${this.txIndex}`;
        const studentName = `Student_W${this.workerIndex}_TX${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        // ISO date string — matches IssueDate format expected by chaincode
        const issueDate   = new Date().toISOString().split('T')[0];   // "YYYY-MM-DD"
        // SHA-256 hash — must match what VerifyCertificate will supply
        const certHash    = crypto
            .createHash('sha256')
            .update(certID + studentName)
            .digest('hex');

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',
            // EXACT order matching Go function signature:
            // IssueCertificate(ctx, id, studentName, degree, issuer, issueDate, certHash)
            contractArguments: [certID, studentName, degree, issuer, issueDate, certHash],
            readOnly:          false,
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
