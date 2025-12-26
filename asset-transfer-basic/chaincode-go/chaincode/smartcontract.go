package chaincode

import (
	"encoding/json"
	"fmt"
	"encoding/hex"             // للتعامل مع مخرجات التشفير
	"golang.org/x/crypto/sha3" // خوارزمية التجزئة المحسنة SHA-3
	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// SmartContract defines the structure for our Diploma Management system
type SmartContract struct {
	contractapi.Contract
}

// Diploma represents the educational certificate data structure
// Added CertificateHash to enhance protection and verify integrity
type Diploma struct {
	DiplomaID       string `json:"DiplomaID"`
	StudentName     string `json:"StudentName"`
	University      string `json:"University"`
	Degree          string `json:"Degree"`
	GraduationYear  int    `json:"GraduationYear"`
	CertificateHash string `json:"CertificateHash"` // البصمة الرقمية المحسنة
}

// generateSHA3Hash توليد بصمة رقمية فريدة باستخدام SHA-3 لتعزيز الأمان
func (s *SmartContract) generateSHA3Hash(diploma Diploma) string {
	// دمج البيانات الأساسية لتكوين السلسلة المطلوب تشفيرها
	input := fmt.Sprintf("%s%s%s%d", diploma.DiplomaID, diploma.StudentName, diploma.University, diploma.GraduationYear)
	
	// استخدام Keccak-256 (SHA-3) لتوليد الهاش
	hash := sha3.New256()
	hash.Write([]byte(input))
	
	return hex.EncodeToString(hash.Sum(nil))
}

// InitLedger adds a base set of diplomas to the ledger for testing purposes
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	diplomas := []Diploma{
		{DiplomaID: "DIP001", StudentName: "Ahmed Ali", University: "UPI", Degree: "Computer Science", GraduationYear: 2024},
		{DiplomaID: "DIP002", StudentName: "Sara Omar", University: "UPI", Degree: "Telecommunication", GraduationYear: 2023},
	}

	for _, diploma := range diplomas {
		// إضافة الهاش للبيانات الأولية
		diploma.CertificateHash = s.generateSHA3Hash(diploma)
		
		diplomaJSON, err := json.Marshal(diploma)
		if err != nil {
			return err
		}

		err = ctx.GetStub().PutState(diploma.DiplomaID, diplomaJSON)
		if err != nil {
			return fmt.Errorf("failed to put to world state. %v", err)
		}
	}
	return nil
}

// CreateDiploma issues a single new diploma with SHA-3 protection
func (s *SmartContract) CreateDiploma(ctx contractapi.TransactionContextInterface, id string, name string, university string, degree string, year int) error {
	exists, err := s.DiplomaExists(ctx, id)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("the diploma %s already exists", id)
	}

	diploma := Diploma{
		DiplomaID:      id,
		StudentName:    name,
		University:     university,
		Degree:         degree,
		GraduationYear: year,
	}
	
	// توليد وتخزين الهاش المحسن
	diploma.CertificateHash = s.generateSHA3Hash(diploma)

	diplomaJSON, err := json.Marshal(diploma)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, diplomaJSON)
}

// CreateDiplomaBatch issues multiple diplomas in a single transaction with SHA-3 for each
// Optimized for high performance (Batching) and high security (SHA-3)
func (s *SmartContract) CreateDiplomaBatch(ctx contractapi.TransactionContextInterface, diplomasJson string) error {
	var diplomas []Diploma
	err := json.Unmarshal([]byte(diplomasJson), &diplomas)
	if err != nil {
		return fmt.Errorf("failed to unmarshal diplomas batch: %v", err)
	}

	for _, diploma := range diplomas {
		// توليد الهاش لكل شهادة داخل الدفعة لضمان سلامة البيانات
		diploma.CertificateHash = s.generateSHA3Hash(diploma)

		diplomaJSON, err := json.Marshal(diploma)
		if err != nil {
			return err
		}
		err = ctx.GetStub().PutState(diploma.DiplomaID, diplomaJSON)
		if err != nil {
			return fmt.Errorf("failed to put diploma %s to world state: %v", diploma.DiplomaID, err)
		}
	}
	return nil
}

// ReadDiploma returns the diploma stored in the world state with given id
func (s *SmartContract) ReadDiploma(ctx contractapi.TransactionContextInterface, id string) (*Diploma, error) {
	diplomaJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if diplomaJSON == nil {
		return nil, fmt.Errorf("the diploma %s does not exist", id)
	}

	var diploma Diploma
	err = json.Unmarshal(diplomaJSON, &diploma)
	if err != nil {
		return nil, err
	}

	return &diploma, nil
}

// VerifyDiploma checks if the diploma data matches its stored SHA-3 hash
// New function for security verification
func (s *SmartContract) VerifyDiploma(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	diploma, err := s.ReadDiploma(ctx, id)
	if err != nil {
		return false, err
	}

	// إعادة حساب الهاش للبيانات الحالية ومقارنته بالمخزن
	calculatedHash := s.generateSHA3Hash(*diploma)
	return calculatedHash == diploma.CertificateHash, nil
}

// DiplomaExists checks if a diploma exists in the world state
func (s *SmartContract) DiplomaExists(ctx contractapi.TransactionContextInterface, hashedID string) (bool, error) {
    // نستخدم hashedID مباشرة كما هو مرسل
    diplomaJSON, err := ctx.GetStub().GetState(hashedID)
    if err != nil {
        return false, fmt.Errorf("failed to read from world state: %v", err)
    }
    return diplomaJSON != nil, nil
}

// GetAllDiplomas returns all diplomas found in world state
func (s *SmartContract) GetAllDiplomas(ctx contractapi.TransactionContextInterface) ([]*Diploma, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	var diplomas []*Diploma
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var diploma Diploma
		err = json.Unmarshal(queryResponse.Value, &diploma)
		if err != nil {
			return nil, err
		}
		diplomas = append(diplomas, &diploma)
	}
	return diplomas, nil
}	

// RevokeCertificate removes a diploma from the ledger to ensure records integrity
// This function represents the "Revocation" phase in the certificate lifecycle
func (s *SmartContract) RevokeCertificate(ctx contractapi.TransactionContextInterface, id string, reason string) error {
    // 1. تشفير الـ ID باستخدام SHA-3 ليتطابق مع ما تم تخزينه
    hash := sha3.New256()
    hash.Write([]byte(id))
    hashedID := hex.EncodeToString(hash.Sum(nil))

    // 2. التحقق من الوجود باستخدام المفتاح المشفر
    exists, err := s.DiplomaExists(ctx, hashedID) // تأكد أن DiplomaExists تقبل الـ hashedID
    if err != nil {
        return err
    }
    if !exists {
        return fmt.Errorf("the diploma with hashed ID %s does not exist", hashedID)
    }

    // 3. الحذف باستخدام المفتاح المشفر
    return ctx.GetStub().DelState(hashedID)
}