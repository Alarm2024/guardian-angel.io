# Guardian Angel Protocol - Technical Architecture & UML

This document provides a comprehensive overview of the system architecture, access control matrices, and data structures governing the `RashidAward` smart contract.

---

## 1. System Architecture Diagram (UML)

The following diagram illustrates the structural design of the contract, including state schemas, modifiers, internal mappings, and the state-machine transitions of proposals and awards.

```mermaid
classDiagram
    class RashidAward {
        <<Smart Contract>>
        +address owner
        +address guardian
        +address verifier
        +address offsetRecipient
        +uint256 offsetBps
        +uint256 constant CHANGE_TIMELOCK
        +bytes32[] proposalIds
        +mapping(uint256 => Award) awards
        +mapping(bytes32 => Proposal) proposals
        +mapping(address => bool) allowedContracts
        
        +constructor(address _guardian, address _verifier, address _offsetRecipient, uint256 _offsetBps)
        +createAward(address recipient, uint256 amount) error NotGuardian
        +verifyAward(uint256 awardId) error NotVerifier
        +distributeAward(uint256 awardId) error ReentrancyGuard
        +proposeChange(bytes32 paramHash, uint256 newValue) error NotOwner
        +approveProposal(bytes32 proposalId) error NotGuardian
        +executeProposal(bytes32 proposalId) error TimelockActive
        +setAllowedContract(address contractAddr, bool allowed) error NotOwner
    }

    class Award {
        <<Struct>>
        +address recipient
        +uint256 amount
        +bool verified
        +bool distributed
        +uint256 createdAt
    }

    class Proposal {
        <<Struct>>
        +bytes32 paramHash
        +uint256 newValue
        +uint256 proposedAt
        +bool approvedByGuardian
        +bool executed
    }

    class Roles {
        <<Enumeration Perspective>>
        OWNER : Institutional Governor
        GUARDIAN : Operational Multisig Layer
        VERIFIER : Ecological Intelligence Oracle
    }

    RashidAward *-- Award : Aggregates & Manages
    RashidAward *-- Proposal : Validates & Enforces
    Roles --> RashidAward : Restricts Functions Via Custom Modifiers
