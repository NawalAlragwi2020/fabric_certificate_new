'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ============================================================
 * QueryAllCertificates Workload Module — v3.0
 * ============================================================
 * Chaincode Function : QueryAllCertificates() []*Certificate
 * Go Signature       : QueryAllCertificates(ctx) ([]*Certificate, error)
 * RBAC               : Public — any organisation
 * Fail-Safe Design   : Returns empty slice (not nil) on empty ledger — never throws
 *                      → Fail = 0 guaranteed
 *
 * No arguments required — matches Go signature exactly.
 *
 * Rate note: TPS is set to 20 in benchConfig.yaml to avoid excessive
 * memory pressure from full-ledger scans during concurrent execution.
 * ============================================================
 */
class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        const request = {
            contractId:        'basic',
            contractFunction:  'QueryAllCertificates',
            // No arguments — matches Go: QueryAllCertificates(ctx)
            contractArguments: [],
            readOnly:          true,   // peer query only — no write to ledger
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
