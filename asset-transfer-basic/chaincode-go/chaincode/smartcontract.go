package chaincode

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// SmartContract defines the structure for our Diploma Management system
type SmartContract struct {
	contractapi.Contract
}

// Diploma represents the educational certificate data structure [cite: 192]
// This structure is designed to prevent forgery and ensure data integrity [cite: 35, 52]
type Diploma struct {
	DiplomaID      string `json:"DiplomaID"`      // المعرف الفريد للشهادة [cite: 192, 251]
	StudentName    string `json:"StudentName"`    // اسم الطالب [cite: 192, 251]
	University     string `json:"University"`     // الجامعة [cite: 192, 251]
	Degree         string `json:"Degree"`         // الدرجة العلمية [cite: 192, 251]
	GraduationYear int    `json:"GraduationYear"` // سنة التخرج [cite: 192, 251]
}

// InitLedger adds a base set of diplomas to the ledger for testing purposes
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	diplomas := []Diploma{
		{DiplomaID: "DIP001", StudentName: "Ahmed Ali", University: "UPI", Degree: "Computer Science", GraduationYear: 2024},
		{DiplomaID: "DIP002", StudentName: "Sara Omar", University: "UPI", Degree: "Telecommunication", GraduationYear: 2023},
	}

	for _, diploma := range diplomas {
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

// CreateDiploma issues a single new diploma to the world state [cite: 251]
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
	diplomaJSON, err := json.Marshal(diploma)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, diplomaJSON)
}

// CreateDiplomaBatch issues multiple diplomas in a single transaction
// This optimized function significantly reduces latency and overhead under high load [cite: 21, 415, 659]
func (s *SmartContract) CreateDiplomaBatch(ctx contractapi.TransactionContextInterface, diplomasJson string) error {
	var diplomas []Diploma
	// Unmarshal the batch of diplomas sent from Caliper [cite: 415]
	err := json.Unmarshal([]byte(diplomasJson), &diplomas)
	if err != nil {
		return fmt.Errorf("failed to unmarshal diplomas batch: %v", err)
	}

	for _, diploma := range diplomas {
		// Store each diploma in the world state
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

// DiplomaExists returns true when diploma with given ID exists in world state
func (s *SmartContract) DiplomaExists(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	diplomaJSON, err := ctx.GetStub().GetState(id)
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
