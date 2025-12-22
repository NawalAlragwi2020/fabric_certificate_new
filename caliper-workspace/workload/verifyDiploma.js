'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class VerifyDiplomaWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        
        // تعديل جوهري: بما أن المعرفات في الإصدار كانت عشوائية تماماً، 
        // سنحاول استهداف المعرفات التي تبدأ بـ DIP_ 
        // في تجارب البحث الحقيقية، يفضل حفظ المعرفات في مصفوفة، 
        // لكن للتبسيط وضمان النجاح سنستخدم معرفاً ثابتاً تم إصداره في البداية (مثل DIP001) 
        // أو محاكاة البحث عن معرف تم إنشاؤه.
        
        const certID = 'DIP001'; // هذا المعرف تم إنشاؤه في وظيفة InitLedger في الكود الذكي

        const request = {
            contractId: 'diploma',
            contractFunction: 'ReadDiploma', 
            contractArguments: [certID],
            readOnly: true
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new VerifyDiplomaWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;