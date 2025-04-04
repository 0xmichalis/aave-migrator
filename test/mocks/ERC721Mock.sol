// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Mock ERC721 token for testing
/// @dev Adds minting capabilities to standard ERC721
contract ERC721Mock is ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    /// @notice Mint a new token
    /// @param to The address to mint to
    /// @param tokenId The token ID to mint
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
