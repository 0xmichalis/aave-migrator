// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import {MintableERC20} from "@aave/contracts/mocks/tokens/MintableERC20.sol";

/// @notice Mock AAVE pool for testing
/// @dev Simplified version that only implements the functions we need
contract AavePoolMock is IPool {
    // Mapping of underlying token to aToken
    mapping(address => address) public aTokens;

    // Custom errors
    error NoATokenForAsset();
    error ATokenAlreadyExists();
    error TransferFailed();

    /// @notice Create a new aToken for an underlying token
    /// @param underlyingToken The token to create an aToken for
    function createAToken(address underlyingToken) external returns (address) {
        require(aTokens[underlyingToken] == address(0), "AToken already exists");

        // Create aToken with same decimals as underlying
        MintableERC20 aToken = new MintableERC20("Aave interest bearing Token", "aToken", 18);
        aTokens[underlyingToken] = address(aToken);
        return address(aToken);
    }

    /// @notice Supply tokens to the pool
    /// @param asset The token to supply
    /// @param amount The amount to supply
    /// @param onBehalfOf The address to supply on behalf of
    /// @param referralCode The referral code (unused)
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        external
        override
    {
        address aToken = aTokens[asset];
        require(aToken != address(0), "No aToken for asset");

        // Transfer underlying token from user to pool
        require(
            MintableERC20(asset).transferFrom(msg.sender, address(this), amount), "Transfer failed"
        );

        // Mint aTokens to recipient
        MintableERC20(aToken).mint(onBehalfOf, amount);

        emit Supply(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    /// @notice Get reserve data for a token
    /// @param asset The token to get data for
    function getReserveData(address asset)
        external
        view
        override
        returns (DataTypes.ReserveDataLegacy memory)
    {
        return DataTypes.ReserveDataLegacy({
            configuration: DataTypes.ReserveConfigurationMap({data: 0}),
            liquidityIndex: 0,
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: aTokens[asset],
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    // Required interface functions that we don't use
    function mintUnbacked(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        external
    {}

    function backUnbacked(address, /* asset */ uint256, /* amount */ uint256 /* fee */ )
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function withdraw(address, /* asset */ uint256, /* amount */ address /* to */ )
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external {}

    function repay(
        address, /* asset */
        uint256, /* amount */
        uint256, /* interestRateMode */
        address /* onBehalfOf */
    ) external pure override returns (uint256) {
        return 0;
    }

    function repayWithATokens(
        address, /* asset */
        uint256, /* amount */
        uint256 /* interestRateMode */
    ) external pure override returns (uint256) {
        return 0;
    }

    function repayWithPermit(
        address, /* asset */
        uint256, /* amount */
        uint256, /* interestRateMode */
        address, /* onBehalfOf */
        uint256, /* deadline */
        uint8, /* permitV */
        bytes32, /* permitR */
        bytes32 /* permitS */
    ) external pure override returns (uint256) {
        return 0;
    }

    function swapBorrowRateMode(address asset, uint256 interestRateMode) external {}

    function rebalanceStableBorrowRate(address asset, address user) external {}

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {}

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external {}

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external {}

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external {}

    function getUserAccountData(address /* user */ )
        external
        pure
        override
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return (0, 0, 0, 0, 0, 0);
    }

    function initReserve(
        address asset,
        address aTokenAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external {
        // No-op in mock
    }

    function dropReserve(address asset) external {}

    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
        external
    {}

    function setConfiguration(
        address asset,
        DataTypes.ReserveConfigurationMap calldata configuration
    ) external {}

    function getConfiguration(address /* asset */ )
        external
        pure
        override
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        return DataTypes.ReserveConfigurationMap(0);
    }

    function getUserConfiguration(address /* user */ )
        external
        pure
        override
        returns (DataTypes.UserConfigurationMap memory)
    {
        return DataTypes.UserConfigurationMap(0);
    }

    function getReserveNormalizedIncome(address /* asset */ )
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function getReserveNormalizedVariableDebt(address /* asset */ )
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external {}

    function getReservesList() external pure override returns (address[] memory) {
        return new address[](0);
    }

    function ADDRESSES_PROVIDER() external pure override returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(address(0));
    }

    function updateBridgeProtocolFee(uint256 bridgeProtocolFee) external {}

    function updateFlashloanPremiums(
        uint128 flashLoanPremiumTotal,
        uint128 flashLoanPremiumToProtocol
    ) external {}

    function configureEModeCategory(
        uint8 id,
        DataTypes.EModeCategoryBaseConfiguration memory config
    ) external {}

    function getEModeCategoryData(uint8 /* id */ )
        external
        pure
        override
        returns (DataTypes.EModeCategoryLegacy memory)
    {
        return DataTypes.EModeCategoryLegacy({
            ltv: 0,
            liquidationThreshold: 0,
            liquidationBonus: 0,
            priceSource: address(0),
            label: ""
        });
    }

    function setUserEMode(uint8 categoryId) external {}

    function getUserEMode(address /* user */ ) external pure override returns (uint256) {
        return 0;
    }

    function resetIsolationModeTotalDebt(address asset) external {}

    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT() external pure returns (uint256) {
        return 0;
    }

    function FLASHLOAN_PREMIUM_TOTAL() external pure override returns (uint128) {
        return 0;
    }

    function BRIDGE_PROTOCOL_FEE() external pure override returns (uint256) {
        return 0;
    }

    function FLASHLOAN_PREMIUM_TO_PROTOCOL() external pure override returns (uint128) {
        return 0;
    }

    function MAX_NUMBER_RESERVES() external pure override returns (uint16) {
        return 0;
    }

    function mintToTreasury(address[] calldata assets) external {}

    function rescueTokens(address token, address to, uint256 amount) external {}

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        external
    {}

    function getReserveAddressById(uint16 /* id */ ) external pure override returns (address) {
        return address(0);
    }

    function getReserveDataLegacy(address asset)
        external
        view
        returns (DataTypes.ReserveDataLegacy memory)
    {
        return DataTypes.ReserveDataLegacy({
            configuration: DataTypes.ReserveConfigurationMap({data: 0}),
            liquidityIndex: 0,
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: aTokens[asset],
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    function getReserveNormalizedIncomeLegacy(address /* asset */ )
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function getReserveNormalizedVariableDebtLegacy(address /* asset */ )
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function getReserveTokensAddresses(address asset)
        external
        view
        returns (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        )
    {
        return (aTokens[asset], address(0), address(0));
    }

    function getReserveConfigurationData(address /* asset */ )
        external
        pure
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        )
    {
        return (18, 0, 0, 0, 0, false, false, false, true, false);
    }

    function getReserveEModeCategory(address /* asset */ ) external pure returns (uint256) {
        return 0;
    }

    function getReserveCaps(address /* asset */ )
        external
        pure
        returns (uint256 borrowCap, uint256 supplyCap)
    {
        return (0, 0);
    }

    function getPaused(address /* asset */ ) external pure returns (bool isPaused) {
        return false;
    }

    function getSiloedBorrowing(address /* asset */ ) external pure returns (bool) {
        return false;
    }

    function getLiquidationProtocolFee(address /* asset */ ) external pure returns (uint256) {
        return 0;
    }

    function getUnbackedMintCap(address /* asset */ ) external pure returns (uint256) {
        return 0;
    }

    function getDebtCeiling(address /* asset */ ) external pure returns (uint256) {
        return 0;
    }

    function getDebtCeilingDecimals() external pure returns (uint256) {
        return 0;
    }

    function getReserveInterestRateStrategyAddress(address /* asset */ )
        external
        pure
        returns (address)
    {
        return address(0);
    }

    function configureEModeCategoryBorrowableBitmap(uint8 id, uint128 borrowableBitmap) external {}

    function configureEModeCategoryCollateralBitmap(uint8 id, uint128 collateralBitmap) external {}

    function eliminateReserveDeficit(address asset, uint256 amount) external {}

    function getBorrowLogic() external pure returns (address) {
        return address(0);
    }

    function getBridgeLogic() external pure returns (address) {
        return address(0);
    }

    function getEModeCategoryBorrowableBitmap(uint8 /* id */ ) external pure returns (uint128) {
        return 0;
    }

    function getEModeCategoryCollateralBitmap(uint8 /* id */ ) external pure returns (uint128) {
        return 0;
    }

    function getEModeCategoryCollateralConfig(uint8 /* id */ )
        external
        pure
        returns (DataTypes.CollateralConfig memory)
    {
        return DataTypes.CollateralConfig({ltv: 0, liquidationThreshold: 0, liquidationBonus: 0});
    }

    function getEModeCategoryLabel(uint8 /* id */ ) external pure returns (string memory) {
        return "";
    }

    function getEModeLogic() external pure returns (address) {
        return address(0);
    }

    function getFlashLoanLogic() external pure returns (address) {
        return address(0);
    }

    function getLiquidationGracePeriod(address /* asset */ ) external pure returns (uint40) {
        return 0;
    }

    function getLiquidationLogic() external pure returns (address) {
        return address(0);
    }

    function getPoolLogic() external pure returns (address) {
        return address(0);
    }

    function getReserveAToken(address asset) external view returns (address) {
        return aTokens[asset];
    }

    function getReserveDeficit(address /* asset */ ) external pure returns (uint256) {
        return 0;
    }

    function getReserveVariableDebtToken(address /* asset */ ) external pure returns (address) {
        return address(0);
    }

    function getReservesCount() external pure returns (uint256) {
        return 0;
    }

    function getSupplyLogic() external pure returns (address) {
        return address(0);
    }

    function getVirtualUnderlyingBalance(address /* asset */ ) external pure returns (uint128) {
        return 0;
    }

    function setLiquidationGracePeriod(address asset, uint40 until) external {}

    function supplyWithPermit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external {}

    function syncIndexesState(address asset) external {}

    function syncRatesState(address asset) external {}
}
