package chaincode

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

type SmartContract struct {
	contractapi.Contract
}

///////////////////////////////////////////////////////////
// Certificate Structure
///////////////////////////////////////////////////////////

type Certificate struct {
	ID          string `json:"ID"`
	StudentName string `json:"StudentName"`
	Degree      string `json:"Degree"`
	Issuer      string `json:"Issuer"`
	IssueDate   string `json:"IssueDate"`
	CertHash    string `json:"CertHash"`
	IsRevoked   bool   `json:"IsRevoked"`
}

///////////////////////////////////////////////////////////
// MSP Helper
///////////////////////////////////////////////////////////

func (s *SmartContract) getClientMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("failed to read client MSP: %v", err)
	}
	return mspID, nil
}

///////////////////////////////////////////////////////////
// 1️⃣ IssueCertificate (Org1 Only)
///////////////////////////////////////////////////////////

func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,   // ✅ الترتيب الصحيح
	certHash string,    // ✅ الترتيب الصحيح
) error {

	mspID, err := s.getClientMSP(ctx)
	if err != nil {
		return err
	}

	if mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1 can issue certificates")
	}

	if id == "" || studentName == "" || degree == "" || issuer == "" || issueDate == "" || certHash == "" {
		return fmt.Errorf("all fields are required")
	}

	exists, err := s.CertificateExists(ctx, id)
	if err != nil {
		return err
	}

	if exists {
		return fmt.Errorf("certificate %s already exists", id)
	}

	cert := Certificate{
		ID:          id,
		StudentName: studentName,
		Degree:      degree,
		Issuer:      issuer,
		IssueDate:   issueDate,
		CertHash:    certHash,
		IsRevoked:   false,
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, certJSON)
}

///////////////////////////////////////////////////////////
// 2️⃣ RevokeCertificate (Org2 Only)
///////////////////////////////////////////////////////////

func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {

	mspID, err := s.getClientMSP(ctx)
	if err != nil {
		return err
	}

	if mspID != "Org2MSP" {
		return fmt.Errorf("access denied: only Org2 can revoke certificates")
	}

	if id == "" {
		return fmt.Errorf("certificate ID is required")
	}

	// ✅ لا نعتبر عدم وجود الشهادة فشل
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return err
	}

	if certJSON == nil {
		return nil
	}

	var cert Certificate
	err = json.Unmarshal(certJSON, &cert)
	if err != nil {
		return err
	}

	if cert.IsRevoked {
		return nil
	}

	cert.IsRevoked = true

	updatedCertJSON, err := json.Marshal(cert)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, updatedCertJSON)
}

///////////////////////////////////////////////////////////
// 3️⃣ VerifyCertificate (Open Read)
///////////////////////////////////////////////////////////

func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (bool, error) {

	if id == "" || certHash == "" {
		return false, fmt.Errorf("certificate ID and hash are required")
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, err
	}

	if certJSON == nil {
		return false, nil
	}

	var cert Certificate
	err = json.Unmarshal(certJSON, &cert)
	if err != nil {
		return false, err
	}

	isValid := cert.CertHash == certHash && !cert.IsRevoked
	return isValid, nil
}

///////////////////////////////////////////////////////////
// Helper
///////////////////////////////////////////////////////////

func (s *SmartContract) CertificateExists(
	ctx contractapi.TransactionContextInterface,
	id string,
) (bool, error) {

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, err
	}

	return certJSON != nil, nil
}
