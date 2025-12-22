'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        this.batchSize = 10; // تجميع 10 شهادات في كل طلب لتقليل العبء
    }

    async submitTransaction() {
        let diplomas = [];
        
        // بناء الدفعة (Batch)
        for (let i = 0; i < this.batchSize; i++) {
            this.txIndex++;
            const certID = `cert_${this.workerIndex}_${this.txIndex}`;
            diplomas.push({
                DiplomaID: certID,
                StudentName: 'Student ' + this.txIndex,
                University: 'UPI University', // متوافق مع هيكل Diploma الجديد
                Degree: 'Computer Science',
                GraduationYear: 2025
            });
        }

        const request = {
            contractId: 'diploma', // يجب أن يطابق الاسم في السكربت وملف الشبكة
            contractFunction: 'CreateDiplomaBatch', // استدعاء الوظيفة المطورة
            contractArguments: [JSON.stringify(diplomas)], // إرسال المصفوفة كـ String واحد
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new IssueCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;