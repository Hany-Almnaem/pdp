# Provable Data Possession - Design Documentation

## Overview
Provable Data Possession (PDP) is a protocol that allows storage providers to prove they possess specific data without revealing the data itself. The system operates through a set of smart contracts that manage proof sets, verification, and fault reporting.

PDP currently enables a client-provider relationship where:
1. Clients and providers establish a proofset for data storage verification
2. Providers add data roots to the proof set and submit periodic proofs
3. The system verifies these proofs using randomized challenges
4. Faults are reported when proofs fail or are not submitted


## Table of Contents
1. [Architecture](#architecture)
2. [Core Components](#core-components)
3. [Data Structures](#data-structures)
4. [Workflows](#workflows)
5. [Security Considerations](#security-considerations)
6. [Performance Considerations](#performance-considerations)
7. [Future Enhancements](#future-enhancements)
8. [Appendices](#appendices)

## Architecture
The PDP system uses a singleton contract design where a single verifier contract manages multiple proof sets for many providers.


### System Components
- **PDP Verifier**: The main contract that holds proof sets and verifies proofs
- **PDP Listener**: Receives events about operations and handles fault logic
- **SimplePDPService**: Manages proving periods and fault reporting
- **Supporting Contracts**: Additional contracts for specific functionality

### Interaction Patterns
The PDP system follows these primary interaction patterns:
1. Clients and providers establish proof sets through the verifier contract
2. Providers add Merkle roots to their proof sets
3. The system issues challenges based on chain randomness
4. Providers submit proofs for verification
5. The listener contract receives events about all operations
6. Faults are reported when proofs fail or are not submitted

## Core Components

### PDP Verifier
- **Purpose**: Manages proof sets and verifies proofs
- **Key methods**:
  - Create proof sets
  - Add/delete roots to proof sets
  - Verify proofs
  - Manage proving periods
- **State management**: Maintains proof set state including roots, sizes, and challenge epochs

### PDP Listener
- **Event handling**: Receives notifications about all operations
- **Interface requirements**: Must implement methods to receive operation events
- **Implementation details**: Handles fault logic and can fail operations

### SimplePDPService
- **Fault handling**: Reports faults when proving fails
- **Proving period management**: Manages the timing of proof challenges
- **Challenge window implementation**: Enforces time constraints for proof submission

## Data Structures
Detailed description of key data structures.

### ProofSet
A proof set is a logical container that holds an ordered collection of Merkle roots representing arrays of data:

```
struct Root {
id: u64
data: CID,
size: u64, // Must be multiple of 32.
}
struct ProofSet {
id: u64,
// Delay in epochs between a successful proof and availability of
// the next challenge.
challengeDelay: u64,
// ID to assign to the next root (a sequence number).
nextRootID: u64,
// Roots in the proof set.
roots: Root[],
// The total size of all roots.
totalSize: u64,
// Epoch from which to draw the next challenge.
nextChallengeEpoch: u64,
}
```

### Proof Structure
Each proof certifies the inclusion of a leaf at a specified position within a Merkle tree:

```
struct Proof {
leaf: bytes32,
leafOffset: uint,
proof: bytes32[],
}
```

### Logical Array Implementation
The PDP Logical Array is implemented using a variant of a Fenwick tree to efficiently manage the concatenated data from all roots in a proof set.

## Workflows
Detailed description of key workflows.

### Proof Set Creation
1. A client and provider agree to set up a proof set
2. They call the verifier contract to create a new proof set
3. The proof set is initialized with owner permissions and challenge parameters

### Data Verification
1. The provider adds Merkle roots to the proof set
2. At each proving period:
   - The system generates random challenges based on chain randomness
   - The provider constructs Merkle proofs for the challenged leaves
   - The provider submits proofs to the verifier contract
   - The contract verifies the proofs and updates the next challenge epoch

### Fault Handling
1. If a provider fails to submit valid proofs within the proving period:
   - The provider must call nextProvingPeriod to acknowledge the fault
   - The listener contract emits an event registering the fault
   - The system updates the next challenge epoch

## Security Considerations

### Threat Model
- Providers may attempt to cheat by not storing data
- Attackers may try to bias randomness or grind proving sets
- Contract ownership could be compromised

### Proofset Independence and Ownership
- Proofset operations are completely independent
- Only the owner of a proofset can impact the result of operations on that proofset

### Soundness
- Proofs are valid only if the provider has the challenged data
- Merkle proofs must be sound
- Randomness cannot be biased through grinding or chain forking

### Completeness
- Proving always works if providing Merkle proofs to the randomly sampled leaves

### Liveness
- Providers can always add new roots to the proofset
- Progress can be made with nextProvingPeriod after data loss or connectivity issues
- Roots can be deleted from proof sets

### Access Control
- Ownership management is strictly enforced
- Only proof set owners can modify their proof sets

### Randomness Handling
- Challenge seed generation uses chain randomness
- A new FEVM precompile is introduced for lookback drand randomness

## Security Considerations
Detailed security analysis.

## Performance Considerations

### Gas Optimization
- The singleton contract design may have higher costs as state grows
- Merkle proof verification is designed to be gas-efficient

### Scalability
- The system can handle multiple proof sets for many providers
- The logical array implementation using a Fenwick tree variant improves efficiency

## Future Enhancements

### Upgradability
- Proxy pattern implementation
- Version management

### Additional Features
- Planned enhancements
- Roadmap

### Glossary
- **Proof Set**: A container for Merkle roots representing data to be proven
- **Merkle Proof**: A cryptographic proof of data inclusion in a Merkle tree
- **Proving Period**: The time window during which proofs must be submitted
- **Challenge**: A random request to prove possession of specific data
