package chaincode

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

type SmartContract struct {
	contractapi.Contract
}

// مفتاح التشفير (يجب أن يكون 32 بايت لـ AES-256)
var encryptionKey = []byte("asupersecretkeythatis32byteslong")

type Certificate struct {
	CertHash    string `json:"CertHash"`
	Degree      string `json:"Degree"`
	ID          string `json:"ID"`
	IsRevoked   bool   `json:"IsRevoked"`
	IssueDate   string `json:"IssueDate"`
	Issuer      string `json:"Issuer"`
	StudentName string `json:"StudentName"`
}

// دالة التشفير المساعدة
func encrypt(text []byte, key []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	ciphertext := make([]byte, aes.BlockSize+len(text))
	iv := ciphertext[:aes.Size]
	if _, err := io.ReadFull(rand.Reader, iv); err != nil {
		return "", err
	}
	stream := cipher.NewCFBEncrypter(block, iv)
	stream.XORKeyStream(ciphertext[aes.BlockSize:], text)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// 1. IssueCertificate: متوافقة تماماً مع ملف JS
func (s *SmartContract) IssueCertificate(ctx contractapi.TransactionContextInterface, id string, studentName string, degree string, issuer string, certHash string, issueDate string) error {
	exists, err := s.CertificateExists(ctx, id)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("الشهادة %s موجودة مسبقاً", id)
	}

	// تشفير اسم الطالب قبل حفظه (لحماية الخصوصية كما في SecureBlockCert)
	encryptedName, err := encrypt([]byte(studentName), encryptionKey)
	if err != nil {
		return fmt.Errorf("فشل التشفير: %v", err)
	}

	cert := Certificate{
		ID:          id,
		StudentName: encryptedName,
		Degree:      degree,
		Issuer:      issuer,
		CertHash:    certHash, // سيستلم الـ HMAC المولد في Caliper
		IssueDate:   issueDate,
		IsRevoked:   false,
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, certJSON)
}

// 4. VerifyCertificate: التحقق من بصمة الشهادة (HMAC)
func (s *SmartContract) VerifyCertificate(ctx contractapi.TransactionContextInterface, id string, certHash string) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil || certJSON == nil {
		return false, fmt.Errorf("الشهادة غير موجودة")
	}

	var cert Certificate
	err = json.Unmarshal(certJSON, &cert)
	if err != nil {
		return false, err
	}

	// مطابقة الـ Hash المرسل من Caliper مع المخزن
	if cert.CertHash == certHash && !cert.IsRevoked {
		return true, nil
	}

	return false, nil
}

// --- وظائف مساعدة ضرورية ---

func (s *SmartContract) CertificateExists(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	return certJSON != nil, err
}
