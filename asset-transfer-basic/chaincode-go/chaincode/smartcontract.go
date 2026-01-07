package chaincode

import (
	"encoding/json"
	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

type SmartContract struct {
	contractapi.Contract
}

type Certificate struct {
	CertHash  string `json:"CertHash"`
	ID        string `json:"ID"`
	IssueDate string `json:"IssueDate"`
	Issuer    string `json:"Issuer"`
	Owner     string `json:"Owner"`
}

// دالة إصدار الشهادة التي سيستدعيها ملف الـ JS
func (s *SmartContract) CreateCertificate(ctx contractapi.TransactionContextInterface, id string, owner string, issuer string, date string, hash string) error {
	cert := Certificate{
		ID:        id,
		Owner:     owner,
		Issuer:    issuer,
		IssueDate: date,
		CertHash:  hash,
	}
	certBytes, err := json.Marshal(cert)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(id, certBytes)
}
