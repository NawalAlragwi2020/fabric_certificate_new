'use strict';

/**
 * Query All Certificates Workload — Round 3
 * ==========================================
 * Invokes: QueryAllCertificates()   [no arguments]
 *
 * Zero-Failure Design:
 *   - readOnly: true → direct peer query, bypasses orderer
 *   - No arguments — Go func takes only ctx
 *   - Chaincode returns empty slice (not nil/error) on empty ledger
 *   - contractArguments: [] — empty array, matches Go signature exactly
 *
 * Public Read: invokerIdentity = User1@org1.example.com
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {

    constructor() {
        super();
    }

    /**
     * Called once before the benchmark round starts.
     */
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractId = roundArguments.contractId || 'basic';
    }

    /**
     * Called for each transaction. Queries QueryAllCertificates.
     *
     * IMPORTANT: contractArguments must be [] (empty array)
     * The Go function signature is: QueryAllCertificates(ctx) — no other args.
     */
    async submitTransaction() {
        const request = {
            contractId: this.contractId,
            contractFunction: 'QueryAllCertificates',
            contractArguments: [],   // ← CRITICAL: empty array, matches Go signature
            invokerIdentity: 'User1@org1.example.com',
            readOnly: true           // ← Direct peer query, no orderer overhead
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
    return new QueryAllCertificatesWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
