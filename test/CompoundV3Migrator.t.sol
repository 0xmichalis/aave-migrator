// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Migrator} from "../src/Migrator.sol";
import {CompoundV3Migrator} from "../src/extensions/CompoundV3Migrator.sol";
import {MigratorTest} from "./Migrator.t.sol";
import {CometMock} from "./mocks/CometMock.sol";
import {IComet} from "../src/extensions/interfaces/IComet.sol";

contract CompoundV3MigratorTest is MigratorTest {
    // Additional state variables
    CompoundV3Migrator compoundMigrator;
    IComet cToken;
    uint256 amount = MINIMUM_POSITION_SIZE * 1e18;

    function setUp() public override {
        super.setUp();

        if (isForkMode) {
            // In fork mode, use existing Compound V3 deployment
            address comet = vm.envOr("COMPOUND_V3_MARKET", address(0));
            require(comet != address(0), "COMPOUND_V3_MARKET must be set in fork mode");
            cToken = IComet(comet);
            token = IERC20(cToken.baseToken());
        } else {
            // In local mode, use mock
            cToken = new CometMock(address(token));
        }

        // Deal tokens to alice
        deal(address(token), alice, amount);

        // Deploy CompoundV3Migrator
        compoundMigrator = new CompoundV3Migrator(
            address(aavePool), address(vrfCoordinator), KEY_HASH, SUBSCRIPTION_ID
        );

        // Add CompoundV3Migrator as VRF consumer
        vrfCoordinator.addConsumer(SUBSCRIPTION_ID, address(compoundMigrator));

        // Set minimum position size
        compoundMigrator.setMinimumPositionSize(address(cToken), MINIMUM_POSITION_SIZE);

        // Label addresses for better trace output
        vm.label(address(compoundMigrator), "CompoundV3Migrator");
        vm.label(address(cToken), "cToken");
    }

    function test_MigrateCompoundV3Position() public {
        // Setup - donate NFT for rewards
        vm.startPrank(bob);
        nft.approve(address(compoundMigrator), 1);
        compoundMigrator.donate(address(nft), 1);
        vm.stopPrank();

        // Setup - supply to Compound and approve migrator
        vm.startPrank(alice);
        token.approve(address(cToken), type(uint256).max);
        CometMock(address(cToken)).supply(address(token), amount);
        IERC20(address(cToken)).approve(address(compoundMigrator), type(uint256).max);

        uint256 aliceCTokenBalanceBefore = IERC20(address(cToken)).balanceOf(alice);
        uint256 migratorCTokenBalanceBefore =
            IERC20(address(cToken)).balanceOf(address(compoundMigrator));
        uint256 aliceATokenBalanceBefore = aToken.balanceOf(alice);
        uint256 migratorATokenBalanceBefore = aToken.balanceOf(address(compoundMigrator));

        // Migrate position
        compoundMigrator.migratePosition(address(cToken), amount);

        // Verify tokens were transferred and aTokens were minted
        uint256 aliceCTokenBalanceAfter = IERC20(address(cToken)).balanceOf(alice);
        uint256 migratorCTokenBalanceAfter =
            IERC20(address(cToken)).balanceOf(address(compoundMigrator));
        uint256 aliceATokenBalanceAfter = aToken.balanceOf(alice);
        uint256 migratorATokenBalanceAfter = aToken.balanceOf(address(compoundMigrator));

        assertApproxEqAbs(
            aliceCTokenBalanceBefore - aliceCTokenBalanceAfter,
            amount,
            1, // Allow for 1 wei rounding error
            "Alice's cToken balance should decrease by the amount migrated"
        );
        assertEq(
            migratorCTokenBalanceBefore - migratorCTokenBalanceAfter,
            0,
            "Migrator's cToken balance should not change"
        );
        assertEq(
            aliceATokenBalanceAfter - aliceATokenBalanceBefore,
            0,
            "Alice's aToken balance should not change"
        );
        assertApproxEqAbs(
            migratorATokenBalanceAfter - migratorATokenBalanceBefore,
            amount,
            1, // Allow for 1 wei rounding error
            "Migrator's aToken balance should increase by the amount migrated"
        );

        // Simulate VRF callback
        uint256 requestId = 1;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123;
        vrfCoordinator.fulfillRandomWords(requestId, address(compoundMigrator));

        // Verify NFT was transferred to user
        assertEq(nft.ownerOf(1), alice);
        (,, bool claimed) = compoundMigrator.rewards(0);
        assertEq(claimed, true);
        vm.stopPrank();
    }
}
