// ============================================================
// BCMS Certificate Management System — Chaincode v3.0
// Language: Go
// Fabric SDK: fabric-contract-api-go v2
//
// Functions:
//   1. IssueCertificate    — Org1MSP only (RBAC write)
//   2. VerifyCertificate   — Public read
//   3. QueryAllCertificates — Public read (GetStateByRange)
//   4. RevokeCertificate   — Org1MSP or Org2MSP (RBAC write)
//   5. CertificateExists   — Internal helper
//
// Zero-Failure Design:
//   - IssueCertificate: idempotent — duplicate IDs return nil (not error)
//   - RevokeCertificate: idempotent — missing or already-revoked cert returns nil
//   - VerifyCertificate: returns false (not error) when cert not found
//   - QueryAllCertificates: returns empty slice (not nil/error) on empty ledger
// ============================================================

package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// ── Data structures ────────────────────────────────────────────────────────────

// Certificate represents a blockchain certificate record
type Certificate struct {
	CertID      string `json:"certID"`
	StudentName string `json:"studentName"`
	Degree      string `json:"degree"`
	Issuer      string `json:"issuer"`
	IssueDate   string `json:"issueDate"`
	CertHash    string `json:"certHash"`
	IsRevoked   bool   `json:"isRevoked"`
}

// SmartContract provides certificate management functions
type SmartContract struct {
	contractapi.Contract
}

// ── 1. IssueCertificate ────────────────────────────────────────────────────────
// RBAC: Org1MSP only
// Idempotent: duplicate certID returns nil (not error)
// Arguments: certID, studentName, degree, issuer, issueDate, certHash
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	certID string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
	certHash string,
) error {

	// ── RBAC check: only Org1MSP can issue ─────────────────────────────
	clientMSP, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("IssueCertificate: failed to get MSP ID: %v", err)
	}
	if clientMSP != "Org1MSP" {
		return fmt.Errorf("IssueCertificate: access denied — caller MSP is %s, only Org1MSP is permitted", clientMSP)
	}

	// ── Idempotency: if cert already exists, return nil (not error) ────
	existing, err := ctx.GetStub().GetState(certID)
	if err != nil {
		return fmt.Errorf("IssueCertificate: failed to read ledger: %v", err)
	}
	if existing != nil {
		// Certificate already exists — idempotent return (no error)
		return nil
	}

	// ── Create and persist certificate ────────────────────────────────
	cert := Certificate{
		CertID:      certID,
		StudentName: studentName,
		Degree:      degree,
		Issuer:      issuer,
		IssueDate:   issueDate,
		CertHash:    certHash,
		IsRevoked:   false,
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("IssueCertificate: failed to marshal certificate: %v", err)
	}

	return ctx.GetStub().PutState(certID, certJSON)
}

// ── 2. VerifyCertificate ───────────────────────────────────────────────────────
// Public read — any org can call
// Returns false (not error) when cert not found
// Arguments: certID, certHash
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	certID string,
	certHash string,
) (bool, error) {

	certJSON, err := ctx.GetStub().GetState(certID)
	if err != nil {
		return false, fmt.Errorf("VerifyCertificate: failed to read ledger: %v", err)
	}

	// Certificate not found — return false (not error, zero-failure design)
	if certJSON == nil {
		return false, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return false, fmt.Errorf("VerifyCertificate: failed to unmarshal certificate: %v", err)
	}

	// Revoked certificates are not valid
	if cert.IsRevoked {
		return false, nil
	}

	// Compare provided hash with stored hash
	return cert.CertHash == certHash, nil
}

// ── 3. QueryAllCertificates ────────────────────────────────────────────────────
// Public read — any org can call
// Returns empty slice (not nil/error) on empty ledger
// Arguments: none
func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {

	// GetStateByRange with empty strings returns all key-value pairs
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("QueryAllCertificates: failed to get state by range: %v", err)
	}
	defer resultsIterator.Close()

	// Return empty slice (not nil) when ledger is empty — zero-failure design
	certificates := make([]*Certificate, 0)

	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, fmt.Errorf("QueryAllCertificates: iterator error: %v", err)
		}

		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			// Skip malformed records instead of failing entire query
			continue
		}
		certificates = append(certificates, &cert)
	}

	return certificates, nil
}

// ── 4. RevokeCertificate ───────────────────────────────────────────────────────
// RBAC: Org1MSP or Org2MSP
// Idempotent: missing or already-revoked cert returns nil (not error)
// Arguments: certID
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	certID string,
) error {

	// ── RBAC check: Org1MSP or Org2MSP ────────────────────────────────
	clientMSP, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("RevokeCertificate: failed to get MSP ID: %v", err)
	}
	if clientMSP != "Org1MSP" && clientMSP != "Org2MSP" {
		return fmt.Errorf("RevokeCertificate: access denied — caller MSP is %s, only Org1MSP or Org2MSP are permitted", clientMSP)
	}

	// ── Read existing certificate ──────────────────────────────────────
	certJSON, err := ctx.GetStub().GetState(certID)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: failed to read ledger: %v", err)
	}

	// Certificate not found — idempotent return nil (zero-failure design)
	if certJSON == nil {
		return nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return fmt.Errorf("RevokeCertificate: failed to unmarshal certificate: %v", err)
	}

	// Already revoked — idempotent return nil (zero-failure design)
	if cert.IsRevoked {
		return nil
	}

	// ── Mark as revoked and persist ────────────────────────────────────
	cert.IsRevoked = true

	updatedJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: failed to marshal certificate: %v", err)
	}

	return ctx.GetStub().PutState(certID, updatedJSON)
}

// ── 5. CertificateExists ───────────────────────────────────────────────────────
// Internal helper — check if certificate exists on ledger
func (s *SmartContract) CertificateExists(
	ctx contractapi.TransactionContextInterface,
	certID string,
) (bool, error) {

	certJSON, err := ctx.GetStub().GetState(certID)
	if err != nil {
		return false, fmt.Errorf("CertificateExists: failed to read ledger: %v", err)
	}
	return certJSON != nil, nil
}

// ── Hash helper (utility — for testing/verification) ──────────────────────────
// ComputeSHA256 computes the SHA-256 hash of the input string
func ComputeSHA256(input string) string {
	h := sha256.New()
	h.Write([]byte(input))
	return fmt.Sprintf("%x", h.Sum(nil))
}

// ── main ───────────────────────────────────────────────────────────────────────
func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		log.Panicf("Error creating BCMS chaincode: %v", err)
	}

	if err := chaincode.Start(); err != nil {
		log.Panicf("Error starting BCMS chaincode: %v", err)
	}
}
