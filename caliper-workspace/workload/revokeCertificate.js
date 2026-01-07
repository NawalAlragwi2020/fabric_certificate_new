'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.workerIndex = -1;
        this.totalWorkers = -1;
    }

    /**
    * تهيئة المتغيرات الأساسية للمختبر
    */
    async initializeWorkloadModule(workerIndex, totalWorkers, numberProtocols, workloadContext) {
        this.workerIndex = workerIndex;
        this.totalWorkers = totalWorkers;
    }

    /**
    * الدالة الأساسية لتنفيذ عملية إلغاء الشهادة
    */
    async submitTransaction() {
        // توليد معرف شهادة لمحاولة إلغائه
        // ملاحظة: في الاختبارات الحقيقية، يجب أن يكون المعرف موجوداً مسبقاً في الليدجر
        // هنا نقوم بإنشاء معرف بناءً على نمط التسمية في ملف issueCertificate
        const certId = `Cert_${this.workerIndex}_${Math.floor(Math.random() * 100)}`;

        const requestSettings = {
            contractId: 'basic',
            contractFunction: 'RevokeCertificate',
            contractArguments: [certId],
            readOnly: false // هذه عملية كتابة (حذف) لذا تتطلب إجماعاً
        };

        await this.sutAdapter.sendRequests(requestSettings);
    }
}

/**
 * تصدير الدالة ليتمكن Caliper من تشغيلها
 */
function createWorkloadModule() {
    return new RevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
