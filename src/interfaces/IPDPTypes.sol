// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPDPTypes
/// @notice Shared types for PDP contracts and consumers
interface IPDPTypes {
    struct RootData {
        // Cids.Cid is imported from Cids.sol, but for interface, use bytes or a minimal struct if needed
        bytes root; // Use bytes for Cid in interface to avoid deep dependency
        uint256 rawSize;
    }

    struct Proof {
        bytes32 leaf;
        bytes32[] proof;
    }

    struct RootIdAndOffset {
        uint256 rootId;
        uint256 offset;
    }
} 