// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Migrator} from "../Migrator.sol";
import {IComet} from "./interfaces/IComet.sol";

contract CompoundV3Migrator is Migrator {
    using SafeERC20 for IERC20;

    error TransferFailed();
    error WithdrawFailed();

    constructor(
        address _aavePool,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) Migrator(_aavePool, _vrfCoordinator, _keyHash, _subscriptionId) {}

    /// @notice Migrate a user's position from Compound v3. The user must approve this contract to transfer their cTokens
    /// @dev Transfers cTokens to this contract and unwraps them to get the underlying token amount
    /// @param token The underlying token address to check
    /// @param amount The amount of cTokens to migrate
    /// @return underlyingToken The underlying token address
    /// @return underlyingAmount The amount of underlying tokens after unwrapping
    function transferTokensForMigration(address token, uint256 amount)
        internal
        override
        returns (address underlyingToken, uint256 underlyingAmount)
    {
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);

        // Get balance before withdrawal to calculate the difference
        IComet comet = IComet(token);
        underlyingToken = comet.baseToken();
        uint256 balanceBefore = IERC20(underlyingToken).balanceOf(address(this));

        // Withdraw underlying tokens
        comet.withdraw(underlyingToken, amount);
        uint256 balanceAfter = IERC20(underlyingToken).balanceOf(address(this));
        underlyingAmount = balanceAfter - balanceBefore;
    }
}
