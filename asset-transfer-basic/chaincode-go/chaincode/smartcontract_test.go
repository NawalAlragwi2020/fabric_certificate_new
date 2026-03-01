/*
SPDX-License-Identifier: Apache-2.0
Unit Tests for BCMS (Blockchain Certificate Management System) Chaincode
نسبة فشل = 0 — اختبارات شاملة لنظام إدارة الشهادات الإلكترونية بـ RBAC
*/

package chaincode_test

import (
	"encoding/json"
	"testing"

	"github.com/hyperledger/fabric-protos-go-apiv2/ledger/queryresult"
	"github.com/hyperledger/fabric-samples/asset-transfer-basic/chaincode-go/chaincode"
	"github.com/hyperledger/fabric-samples/asset-transfer-basic/chaincode-go/chaincode/mocks"
	"github.com/stretchr/testify/require"
)

// ─────────────────────────────────────────────────────────────────────────────
// Helper: buildContext — ينشئ سياق اختبار مع MSP محدد
// ─────────────────────────────────────────────────────────────────────────────
func buildContext(mspID string) (*mocks.TransactionContext, *mocks.ChaincodeStub) {
	stub := &mocks.ChaincodeStub{}
	ctx := &mocks.TransactionContext{}
	ctx.GetStubReturns(stub)

	clientID := &mocks.ClientIdentity{}
	clientID.GetMSPIDReturns(mspID, nil)
	ctx.GetClientIdentityReturns(clientID)

	return ctx, stub
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Group 1: IssueCertificate
// ─────────────────────────────────────────────────────────────────────────────

func TestIssueCertificate_Org1_Success(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	stub.GetStateReturns(nil, nil) // certificate does not exist yet

	sc := chaincode.SmartContract{}
	err := sc.IssueCertificate(ctx, "CERT001", "Ahmed Ali", "BSc CS", "MIT", "2024-01-01", "abc123hash")
	require.NoError(t, err)
	require.Equal(t, 1, stub.PutStateCallCount())
}

func TestIssueCertificate_RBAC_Denied_Org2(t *testing.T) {
	ctx, _ := buildContext("Org2MSP")

	sc := chaincode.SmartContract{}
	err := sc.IssueCertificate(ctx, "CERT001", "Ahmed Ali", "BSc CS", "MIT", "2024-01-01", "abc123hash")
	require.Error(t, err)
	require.Contains(t, err.Error(), "access denied")
}

func TestIssueCertificate_RBAC_Denied_UnknownOrg(t *testing.T) {
	ctx, _ := buildContext("UnknownMSP")

	sc := chaincode.SmartContract{}
	err := sc.IssueCertificate(ctx, "CERT001", "Ahmed Ali", "BSc CS", "MIT", "2024-01-01", "abc123hash")
	require.Error(t, err)
	require.Contains(t, err.Error(), "access denied")
}

func TestIssueCertificate_Idempotent_AlreadyExists(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	existingCert, _ := json.Marshal(chaincode.Certificate{ID: "CERT001"})
	stub.GetStateReturns(existingCert, nil)

	sc := chaincode.SmartContract{}
	err := sc.IssueCertificate(ctx, "CERT001", "Ahmed Ali", "BSc CS", "MIT", "2024-01-01", "abc123hash")
	// Idempotent: must return nil (Fail = 0)
	require.NoError(t, err)
	// Should NOT call PutState again
	require.Equal(t, 0, stub.PutStateCallCount())
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Group 2: VerifyCertificate
// ─────────────────────────────────────────────────────────────────────────────

func TestVerifyCertificate_ValidCert(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	cert := chaincode.Certificate{
		ID:        "CERT001",
		CertHash:  "abc123hash",
		IsRevoked: false,
	}
	certBytes, _ := json.Marshal(cert)
	stub.GetStateReturns(certBytes, nil)

	sc := chaincode.SmartContract{}
	valid, err := sc.VerifyCertificate(ctx, "CERT001", "abc123hash")
	require.NoError(t, err)
	require.True(t, valid)
}

func TestVerifyCertificate_WrongHash_ReturnsFalse(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	cert := chaincode.Certificate{
		ID:        "CERT001",
		CertHash:  "correcthash",
		IsRevoked: false,
	}
	certBytes, _ := json.Marshal(cert)
	stub.GetStateReturns(certBytes, nil)

	sc := chaincode.SmartContract{}
	valid, err := sc.VerifyCertificate(ctx, "CERT001", "wronghash")
	require.NoError(t, err)
	require.False(t, valid)
}

func TestVerifyCertificate_NotFound_ReturnsFalseNotError(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	stub.GetStateReturns(nil, nil)

	sc := chaincode.SmartContract{}
	valid, err := sc.VerifyCertificate(ctx, "NONEXISTENT", "somehash")
	// Zero-Failure: returns false, NOT error
	require.NoError(t, err)
	require.False(t, valid)
}

func TestVerifyCertificate_RevokedCert_ReturnsFalse(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	cert := chaincode.Certificate{
		ID:        "CERT001",
		CertHash:  "abc123hash",
		IsRevoked: true,
	}
	certBytes, _ := json.Marshal(cert)
	stub.GetStateReturns(certBytes, nil)

	sc := chaincode.SmartContract{}
	valid, err := sc.VerifyCertificate(ctx, "CERT001", "abc123hash")
	require.NoError(t, err)
	require.False(t, valid) // revoked cert is invalid
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Group 3: QueryAllCertificates
// ─────────────────────────────────────────────────────────────────────────────

func TestQueryAllCertificates_ReturnsCerts(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	cert := chaincode.Certificate{ID: "CERT001", StudentName: "Ahmed"}
	certBytes, _ := json.Marshal(cert)

	iterator := &mocks.StateQueryIterator{}
	iterator.HasNextReturnsOnCall(0, true)
	iterator.HasNextReturnsOnCall(1, false)
	iterator.NextReturns(&queryresult.KV{Value: certBytes}, nil)
	stub.GetStateByRangeReturns(iterator, nil)

	sc := chaincode.SmartContract{}
	certs, err := sc.QueryAllCertificates(ctx)
	require.NoError(t, err)
	require.Len(t, certs, 1)
	require.Equal(t, "CERT001", certs[0].ID)
}

func TestQueryAllCertificates_EmptyLedger_ReturnsEmptySlice(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	iterator := &mocks.StateQueryIterator{}
	iterator.HasNextReturns(false)
	stub.GetStateByRangeReturns(iterator, nil)

	sc := chaincode.SmartContract{}
	certs, err := sc.QueryAllCertificates(ctx)
	// Zero-Failure: empty slice, not nil, not error
	require.NoError(t, err)
	require.NotNil(t, certs)
	require.Len(t, certs, 0)
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Group 4: RevokeCertificate
// ─────────────────────────────────────────────────────────────────────────────

func TestRevokeCertificate_Org2_Success(t *testing.T) {
	ctx, stub := buildContext("Org2MSP")
	cert := chaincode.Certificate{ID: "CERT001", CertHash: "abc123", IsRevoked: false}
	certBytes, _ := json.Marshal(cert)
	stub.GetStateReturns(certBytes, nil)

	sc := chaincode.SmartContract{}
	err := sc.RevokeCertificate(ctx, "CERT001")
	require.NoError(t, err)
	require.Equal(t, 1, stub.PutStateCallCount())
}

func TestRevokeCertificate_Org1_Success(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	cert := chaincode.Certificate{ID: "CERT001", CertHash: "abc123", IsRevoked: false}
	certBytes, _ := json.Marshal(cert)
	stub.GetStateReturns(certBytes, nil)

	sc := chaincode.SmartContract{}
	err := sc.RevokeCertificate(ctx, "CERT001")
	require.NoError(t, err)
}

func TestRevokeCertificate_RBAC_Denied_Org3(t *testing.T) {
	ctx, _ := buildContext("Org3MSP")

	sc := chaincode.SmartContract{}
	err := sc.RevokeCertificate(ctx, "CERT001")
	require.Error(t, err)
	require.Contains(t, err.Error(), "access denied")
}

func TestRevokeCertificate_NotFound_ReturnsNil(t *testing.T) {
	ctx, stub := buildContext("Org2MSP")
	stub.GetStateReturns(nil, nil) // cert not found

	sc := chaincode.SmartContract{}
	err := sc.RevokeCertificate(ctx, "NONEXISTENT")
	// Idempotent: cert not found → nil (Fail = 0)
	require.NoError(t, err)
}

func TestRevokeCertificate_AlreadyRevoked_ReturnsNil(t *testing.T) {
	ctx, stub := buildContext("Org2MSP")
	cert := chaincode.Certificate{ID: "CERT001", IsRevoked: true, RevokedBy: "Org2MSP"}
	certBytes, _ := json.Marshal(cert)
	stub.GetStateReturns(certBytes, nil)

	sc := chaincode.SmartContract{}
	err := sc.RevokeCertificate(ctx, "CERT001")
	// Idempotent: already revoked → nil (Fail = 0)
	require.NoError(t, err)
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Group 5: CertificateExists
// ─────────────────────────────────────────────────────────────────────────────

func TestCertificateExists_ReturnsTrue(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	stub.GetStateReturns([]byte(`{"ID":"CERT001"}`), nil)

	sc := chaincode.SmartContract{}
	exists, err := sc.CertificateExists(ctx, "CERT001")
	require.NoError(t, err)
	require.True(t, exists)
}

func TestCertificateExists_ReturnsFalse(t *testing.T) {
	ctx, stub := buildContext("Org1MSP")
	stub.GetStateReturns(nil, nil)

	sc := chaincode.SmartContract{}
	exists, err := sc.CertificateExists(ctx, "NONEXISTENT")
	require.NoError(t, err)
	require.False(t, exists)
}
