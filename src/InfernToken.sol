// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Infernidentity.md (INFERN)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract InfernToken is ERC20 {
    /// @notice One billion tokens, expressed in the smallest unit (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev When created by a factory, the factory receives the entire supply.
    constructor() ERC20("Infernidentity.md", "INFERN") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
