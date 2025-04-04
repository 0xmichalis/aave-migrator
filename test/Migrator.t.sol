// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";
import {MintableERC20} from "@aave/contracts/mocks/tokens/MintableERC20.sol";
import {VRFCoordinatorV2Mock} from
    "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Migrator} from "../src/Migrator.sol";
import {AavePoolMock} from "./mocks/AavePoolMock.sol";
import {ERC721Mock} from "./mocks/ERC721Mock.sol";

contract MigratorTest is Test {
    // Users
    address alice;
    address bob;

    // Contracts
    Migrator migrator;
    VRFCoordinatorV2Mock vrfCoordinator;
    MintableERC20 token;
    ERC721Mock nft;
    AavePoolMock aavePool;
    IERC20 aToken;

    // Constants
    bytes32 constant KEY_HASH = bytes32(uint256(1));
    uint64 constant SUBSCRIPTION_ID = 1;
    uint32 constant CALLBACK_GAS_LIMIT = 100000;
    uint256 constant MINIMUM_POSITION_SIZE = 1000;

    function setUp() public {
        // Create users
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Deploy mock VRF Coordinator
        vrfCoordinator = new VRFCoordinatorV2Mock(
            0.1 ether, // Base fee
            1e9 // Gas price link per gas
        );

        // Create and fund subscription
        vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(SUBSCRIPTION_ID, 10 ether);

        // Deploy mock ERC20 token
        token = new MintableERC20("Fartcoin", "FARTCOIN", 18);
        token.mint(alice, 1000000 ether);

        // Deploy mock ERC721
        nft = new ERC721Mock("Cryptopunks", "PUNK");
        nft.mint(bob, 1);
        nft.mint(bob, 2);

        // Deploy mock AAVE pool and create aToken
        aavePool = new AavePoolMock();
        aToken = IERC20(aavePool.createAToken(address(token)));

        // Deploy Migrator
        migrator =
            new Migrator(address(aavePool), address(vrfCoordinator), KEY_HASH, SUBSCRIPTION_ID);

        // Add Migrator as VRF consumer
        vrfCoordinator.addConsumer(SUBSCRIPTION_ID, address(migrator));

        // Set minimum position size
        migrator.setMinimumPositionSize(address(token), MINIMUM_POSITION_SIZE);

        // Label addresses for better trace output
        vm.label(address(migrator), "Migrator");
        vm.label(address(vrfCoordinator), "VRFCoordinator");
        vm.label(address(token), "Token");
        vm.label(address(nft), "NFT");
        vm.label(address(aavePool), "AavePool");
        vm.label(address(aToken), "aToken");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
    }

    function test_DonateNFT() public {
        // Setup
        vm.startPrank(bob);
        nft.approve(address(migrator), 1);

        // Donate NFT
        migrator.donate(address(nft), 1);
        vm.stopPrank();

        // Verify NFT was transferred
        assertEq(nft.ownerOf(1), address(migrator));
    }

    function test_DonateBatchNFTs() public {
        // Setup
        vm.startPrank(bob);
        nft.approve(address(migrator), 1);
        nft.approve(address(migrator), 2);

        // Create arrays for batch donation
        address[] memory nfts = new address[](2);
        nfts[0] = address(nft);
        nfts[1] = address(nft);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        // Donate NFTs
        migrator.donateBatch(nfts, tokenIds);
        vm.stopPrank();

        // Verify NFTs were transferred
        assertEq(nft.ownerOf(1), address(migrator));
        assertEq(nft.ownerOf(2), address(migrator));
        (address erc721, uint256 tokenId, bool claimed) = migrator.rewards(0);
        assertEq(erc721, address(nft));
        assertEq(tokenId, 1);
        assertEq(claimed, false);
        (erc721, tokenId, claimed) = migrator.rewards(1);
        assertEq(erc721, address(nft));
        assertEq(tokenId, 2);
        assertEq(claimed, false);
    }

    function test_MigratePosition() public {
        // Setup - donate NFT for rewards
        vm.startPrank(bob);
        nft.approve(address(migrator), 1);
        migrator.donate(address(nft), 1);
        vm.stopPrank();

        // Setup - approve tokens
        vm.startPrank(alice);
        token.approve(address(migrator), type(uint256).max);

        // Migrate position
        uint256 amount = MINIMUM_POSITION_SIZE;
        migrator.migratePosition(address(token), amount);

        // Verify tokens were transferred and aTokens were minted
        assertEq(token.balanceOf(alice), 1000000 ether - amount);
        assertEq(token.balanceOf(address(aavePool)), amount);
        assertEq(aToken.balanceOf(address(migrator)), amount);

        // Simulate VRF callback
        uint256 requestId = 1;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123;
        vrfCoordinator.fulfillRandomWords(requestId, address(migrator));

        // Verify NFT was transferred to user
        assertEq(nft.ownerOf(1), alice);
        (,, bool claimed) = migrator.rewards(0);
        assertEq(claimed, true);
        vm.stopPrank();
    }

    function test_ClaimAavePosition() public {
        // First migrate a position
        test_MigratePosition();

        // Try to claim before cooldown - should revert
        vm.startPrank(alice);
        vm.expectRevert(Migrator.CooldownActive.selector);
        migrator.claimAavePosition(address(token));

        // Wait for cooldown
        skip(30 days);

        // Claim position
        migrator.claimAavePosition(address(token));

        // Verify aTokens were transferred
        assertEq(aToken.balanceOf(alice), MINIMUM_POSITION_SIZE);
        assertEq(aToken.balanceOf(address(migrator)), 0);
        vm.stopPrank();
    }
}
