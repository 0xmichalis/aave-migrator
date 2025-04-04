// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IComet} from "../../src/extensions/interfaces/IComet.sol";

contract CometMock is IComet, ERC20 {
    using SafeERC20 for IERC20;

    error InsufficientBalance(uint256 balance, uint256 needed);

    address public override baseToken;

    constructor(address _baseToken) ERC20("Compound v3 Token", "cToken") {
        baseToken = _baseToken;
    }

    function withdraw(address asset, uint256 amount) external override {
        require(asset == baseToken, "CometMock: invalid asset");
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) {
            revert InsufficientBalance(balance, amount);
        }

        // Burn cTokens
        _burn(msg.sender, amount);

        // Transfer underlying tokens
        IERC20(baseToken).safeTransfer(msg.sender, amount);
    }

    function supply(address asset, uint256 amount) external {
        require(asset == baseToken, "CometMock: invalid asset");

        // Transfer underlying tokens from sender
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), amount);

        // Mint cTokens 1:1 (simplified for testing)
        _mint(msg.sender, amount);
    }
}
