// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

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
    // Test mode
    bool internal isForkMode;

    // Users
    address alice;
    address bob;

    // Contracts
    Migrator migrator;
    VRFCoordinatorV2Mock vrfCoordinator;
    IERC20 token;
    ERC721Mock nft;
    IPool aavePool;
    IERC20 aToken;

    // Constants
    bytes32 constant KEY_HASH = bytes32(uint256(1));
    uint64 constant SUBSCRIPTION_ID = 1;
    uint32 constant CALLBACK_GAS_LIMIT = 100000;
    uint256 constant MINIMUM_POSITION_SIZE = 1000;

    function setUp() public {
        // Check if we're in fork mode
        isForkMode = vm.envOr("FORK_MODE", false);

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

        if (isForkMode) {
            // In fork mode, use existing contracts from the network
            address aavePoolAddress = vm.envOr("AAVE_POOL_ADDRESS", address(0));
            address tokenAddress = vm.envOr("ERC20_TOKEN_ADDRESS", address(0));

            require(aavePoolAddress != address(0), "AAVE_POOL_ADDRESS must be set in fork mode");
            require(tokenAddress != address(0), "ERC20_TOKEN_ADDRESS must be set in fork mode");

            aavePool = IPool(aavePoolAddress);
            token = IERC20(tokenAddress);

            // Get the aToken address from the AAVE pool
            address aTokenAddress = aavePool.getReserveData(address(token)).aTokenAddress;
            require(aTokenAddress != address(0), "aToken not found for the provided token");
            aToken = IERC20(aTokenAddress);

            // Ensure Alice has enough tokens
            deal(address(token), alice, MINIMUM_POSITION_SIZE * 1000);
        } else {
            // In local mode, deploy mock contracts
            // Deploy mock ERC20 token
            MintableERC20 mockToken = new MintableERC20("Fartcoin", "FARTCOIN", 18);
            mockToken.mint(alice, 1000000 ether);
            token = IERC20(address(mockToken));

            // Deploy mock AAVE pool and create aToken
            AavePoolMock mockAavePool = new AavePoolMock();
            aavePool = mockAavePool;
            aToken = IERC20(mockAavePool.createAToken(address(token)));
        }

        // Deploy mock ERC721
        nft = new ERC721Mock("Cryptopunks", "PUNK");
        nft.mint(bob, 1);
        nft.mint(bob, 2);

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

        uint256 aliceTokenBalanceBefore = token.balanceOf(alice);
        uint256 migratorTokenBalanceBefore = token.balanceOf(address(migrator));
        uint256 aliceATokenBalanceBefore = aToken.balanceOf(alice);
        uint256 migratorATokenBalanceBefore = aToken.balanceOf(address(migrator));

        // Migrate position
        uint256 amount = MINIMUM_POSITION_SIZE;
        migrator.migratePosition(address(token), amount);

        // Verify tokens were transferred and aTokens were minted
        uint256 aliceTokenBalanceAfter = token.balanceOf(alice);
        uint256 migratorTokenBalanceAfter = token.balanceOf(address(migrator));
        uint256 aliceATokenBalanceAfter = aToken.balanceOf(alice);
        uint256 migratorATokenBalanceAfter = aToken.balanceOf(address(migrator));

        assertEq(
            aliceTokenBalanceBefore - aliceTokenBalanceAfter,
            amount,
            "Alice's token balance should decrease by the amount migrated"
        );
        assertEq(
            migratorTokenBalanceBefore - migratorTokenBalanceAfter,
            0,
            "Migrator's token balance should not change"
        );
        assertEq(
            aliceATokenBalanceAfter - aliceATokenBalanceBefore,
            0,
            "Alice's aToken balance should not change"
        );
        assertEq(
            migratorATokenBalanceAfter - migratorATokenBalanceBefore,
            amount,
            "Migrator's aToken balance should increase by the amount migrated"
        );

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

        // Get the normalized income right after migration
        uint256 initialNormalizedIncome =
            IPool(address(aavePool)).getReserveNormalizedIncome(address(token));

        // Try to claim before cooldown - should revert
        vm.startPrank(alice);
        vm.expectRevert(Migrator.CooldownActive.selector);
        migrator.claimAavePosition(address(token));

        // Wait for cooldown and let interest accrue
        skip(30 days);

        // Claim position
        migrator.claimAavePosition(address(token));

        // Get final normalized income
        uint256 finalNormalizedIncome =
            IPool(address(aavePool)).getReserveNormalizedIncome(address(token));

        // Verify aTokens were transferred
        uint256 aliceTokenBalanceAfterClaim = aToken.balanceOf(alice);
        uint256 migratorTokenBalanceAfterClaim = aToken.balanceOf(address(migrator));

        // Calculate expected amount with interest
        uint256 expectedAmount =
            (MINIMUM_POSITION_SIZE * finalNormalizedIncome) / initialNormalizedIncome;

        // Verify Alice received the correct amount with interest
        assertApproxEqAbs(
            aliceTokenBalanceAfterClaim,
            expectedAmount,
            1, // Allow for 1 wei rounding error
            "Alice should receive original amount plus interest"
        );

        // Verify Migrator's balance is close to 0 (may have dust from rounding)
        assertApproxEqAbs(
            migratorTokenBalanceAfterClaim,
            0,
            1, // Allow for 1 wei rounding error
            "Migrator should have no aTokens left (except dust)"
        );

        vm.stopPrank();
    }
}
