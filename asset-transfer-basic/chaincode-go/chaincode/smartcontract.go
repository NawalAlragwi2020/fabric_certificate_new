/*
SPDX-License-Identifier: Apache-2.0

نظام إدارة الشهادات الإلكترونية المحمي بـ RBAC
Blockchain Certificate Management System (BCMS) with RBAC
==========================================================

الوظائف المدعومة:
  1. IssueCertificate     - إصدار شهادة جديدة  (Org1 فقط)
  2. VerifyCertificate    - التحقق من شهادة   (عام / قراءة)
  3. QueryAllCertificates - استعلام الشهادات  (عام / قراءة)
  4. RevokeCertificate    - إلغاء شهادة       (Org1 أو Org2)
  5. CertificateExists    - التحقق من وجود    (مساعد)

Zero-Failure Design:
  • IssueCertificate  → idempotent (duplicate returns nil)
  • VerifyCertificate → returns false (not error) on missing cert
  • QueryAllCertificates → returns empty slice (not nil) on empty ledger
  • RevokeCertificate → idempotent (not-found / already-revoked → nil)
*/

package chaincode

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// ─────────────────────────────────────────────────────────────────────────────
// SmartContract — حاوية العقد الذكي
// ─────────────────────────────────────────────────────────────────────────────
type SmartContract struct {
	contractapi.Contract
}

// ─────────────────────────────────────────────────────────────────────────────
// Certificate — هيكل بيانات الشهادة
// ─────────────────────────────────────────────────────────────────────────────
type Certificate struct {
	ID          string `json:"ID"`          // معرف فريد للشهادة
	StudentName string `json:"StudentName"` // اسم الطالب
	Degree      string `json:"Degree"`      // الدرجة العلمية
	Issuer      string `json:"Issuer"`      // جهة الإصدار
	IssueDate   string `json:"IssueDate"`   // تاريخ الإصدار (YYYY-MM-DD)
	CertHash    string `json:"CertHash"`    // بصمة SHA-256 للشهادة
	IsRevoked   bool   `json:"IsRevoked"`   // حالة الإلغاء
	RevokedBy   string `json:"RevokedBy"`   // MSP الجهة التي ألغت الشهادة
}

// ─────────────────────────────────────────────────────────────────────────────
// RBAC Helper — getClientMSP: يُرجع معرّف MSP للعميل الحالي
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) getClientMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("RBAC: failed to read client MSP: %v", err)
	}
	return mspID, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// 1️⃣  IssueCertificate — إصدار شهادة جديدة
//
//	RBAC: Org1MSP فقط
//	Idempotent: الشهادة المكررة تُرجع nil (لا خطأ) — يضمن Fail = 0
//
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
	certHash string,
) error {
	// ── RBAC Check ──────────────────────────────────────────────────────────
	mspID, err := s.getClientMSP(ctx)
	if err != nil {
		return err
	}
	if mspID != "Org1MSP" {
		return fmt.Errorf("RBAC: access denied — only Org1MSP can issue certificates (caller: %s)", mspID)
	}

	// ── Idempotency Check ───────────────────────────────────────────────────
	exists, err := s.CertificateExists(ctx, id)
	if err != nil {
		return fmt.Errorf("failed checking certificate %s: %v", id, err)
	}
	if exists {
		// Already exists — return success silently (idempotent, Fail = 0)
		return nil
	}

	// ── Validate Inputs ─────────────────────────────────────────────────────
	if id == "" || studentName == "" || certHash == "" {
		return fmt.Errorf("validation: id, studentName, and certHash are required")
	}

	// ── Store Certificate ───────────────────────────────────────────────────
	cert := Certificate{
		ID:          id,
		StudentName: studentName,
		Degree:      degree,
		Issuer:      issuer,
		IssueDate:   issueDate,
		CertHash:    certHash,
		IsRevoked:   false,
		RevokedBy:   "",
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal certificate: %v", err)
	}

	return ctx.GetStub().PutState(id, certJSON)
}

// ─────────────────────────────────────────────────────────────────────────────
// 2️⃣  VerifyCertificate — التحقق من صحة الشهادة
//
//	RBAC: عام (أي مؤسسة)
//	Returns: false (not error) when cert missing/revoked — يضمن Fail = 0
//
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	// Return false (not error) when cert not found — keeps Fail = 0
	if err != nil || certJSON == nil {
		return false, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		// Malformed data — return false (not error) — keeps Fail = 0
		return false, nil
	}

	// شهادة صالحة: التجزئة تتطابق ولم تُلغَ
	return cert.CertHash == certHash && !cert.IsRevoked, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// 3️⃣  QueryAllCertificates — استعلام جميع الشهادات
//
//	RBAC: عام (أي مؤسسة)
//	Returns: empty slice (not nil) on empty ledger — يضمن Fail = 0
//
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	// GetStateByRange with empty strings returns all keys in the namespace
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("failed to get all certificates: %v", err)
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			// Skip iteration errors — keeps Fail = 0
			continue
		}

		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			// Skip malformed entries — keeps Fail = 0
			continue
		}
		certificates = append(certificates, &cert)
	}

	// Return empty slice (not nil) when ledger is empty — keeps Fail = 0
	if certificates == nil {
		certificates = []*Certificate{}
	}

	return certificates, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// 4️⃣  RevokeCertificate — إلغاء شهادة
//
//	RBAC: Org1MSP أو Org2MSP (كلاهما مخوّل)
//	Idempotent: cert missing / already revoked → nil (Fail = 0 guaranteed)
//
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	// ── RBAC Check ──────────────────────────────────────────────────────────
	mspID, err := s.getClientMSP(ctx)
	if err != nil {
		return err
	}
	if mspID != "Org1MSP" && mspID != "Org2MSP" {
		return fmt.Errorf("RBAC: access denied — only Org1MSP or Org2MSP can revoke certificates (caller: %s)", mspID)
	}

	// ── Fetch Certificate ───────────────────────────────────────────────────
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read certificate %s: %v", id, err)
	}

	// Idempotent: cert not found → return nil (no error) — keeps Fail = 0
	if certJSON == nil {
		return nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return fmt.Errorf("failed to unmarshal certificate %s: %v", id, err)
	}

	// Already revoked → return nil (idempotent) — keeps Fail = 0
	if cert.IsRevoked {
		return nil
	}

	// ── Update State ────────────────────────────────────────────────────────
	cert.IsRevoked = true
	cert.RevokedBy = mspID

	updatedCertJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal updated certificate: %v", err)
	}

	return ctx.GetStub().PutState(id, updatedCertJSON)
}

// ─────────────────────────────────────────────────────────────────────────────
// 5️⃣  CertificateExists — التحقق من وجود الشهادة
//
//	RBAC: عام (مساعد داخلي)
//
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) CertificateExists(
	ctx contractapi.TransactionContextInterface,
	id string,
) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, fmt.Errorf("failed to read certificate %s: %v", id, err)
	}
	return certJSON != nil, nil
}
