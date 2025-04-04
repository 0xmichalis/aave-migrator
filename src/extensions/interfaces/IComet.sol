// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IComet
/// @notice Interface for Compound v3's Comet (cToken) contract
interface IComet {
    function baseToken() external view returns (address);
    function withdraw(address asset, uint256 amount) external;
}
