// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VRFCoordinatorV2Interface} from
    "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/// @title Migrator
/// @notice Migrates positions to AAVE v3 while offering ERC721s as rewards.
/// Donated NFTs are distributed as rewards for successful migrations.
contract Migrator is Ownable, ReentrancyGuard, IERC721Receiver, VRFConsumerBaseV2 {
    using SafeERC20 for IERC20;

    // Custom Errors
    error TokenNotSupported(address token);
    error RewardAlreadyClaimed();
    error NoRewardsAvailable();
    error PositionTooSmall(address token, uint256 amount, uint256 minRequired);
    error InvalidRequestId();
    error RequestIdMismatch();
    error ArrayLengthMismatch();
    error CooldownActive();
    error ApproveFailed();

    // Constants & immutable variables
    uint256 public constant COOLDOWN_PERIOD = 30 days;
    uint16 public constant AAVE_REFERRAL_CODE = 0;
    address public immutable AAVE_POOL;

    // Chainlink VRF Configuration
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    bytes32 public immutable KEY_HASH;
    uint64 public immutable SUBSCRIPTION_ID;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;
    uint32 public constant CALLBACK_GAS_LIMIT = 100000;

    // Structs
    struct MigrationRequest {
        bool hasClaimedReward;
        uint256 requestId;
        uint256 amount;
        uint256 timestamp;
    }

    struct Position {
        address user;
        address token;
    }

    struct ERC721Reward {
        address erc721;
        uint256 tokenId;
        bool claimed;
    }

    // State variables
    // user => token => request
    mapping(address => mapping(address => MigrationRequest)) public requests;
    // Inverse mapping from requestId to position so the Chainlink callback
    // can reward the correct user
    mapping(uint256 => Position) public positions;
    // Minimum position size for each token
    mapping(address => uint256) public minimumPositionSize;
    // Array of rewards
    ERC721Reward[] public rewards;
    // Array of indices pointing to unclaimed rewards in the rewards array
    uint256[] private unclaimedRewardIndices;

    // Events
    event Donated(address indexed donor, address indexed erc721, uint256 tokenId);
    event Claimed(address indexed user, address indexed erc721, uint256 tokenId);
    event MinimumPositionSizeSet(address indexed token, uint256 minimumSize);

    /// @notice Constructor to initialize the contract
    /// @param aavePool_ The AAVE v3 pool address
    /// @param vrfCoordinator_ The Chainlink VRF Coordinator address
    /// @param keyHash_ The key hash for VRF
    /// @param subscriptionId_ The subscription ID for VRF
    constructor(
        address aavePool_,
        address vrfCoordinator_,
        bytes32 keyHash_,
        uint64 subscriptionId_
    ) VRFConsumerBaseV2(vrfCoordinator_) Ownable(msg.sender) {
        AAVE_POOL = aavePool_;
        VRF_COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator_);
        KEY_HASH = keyHash_;
        SUBSCRIPTION_ID = subscriptionId_;
    }

    /// @notice Configure a token and its minimum position size
    /// @param token The token address
    /// @param minSize The minimum position size (in token decimals)
    function setMinimumPositionSize(address token, uint256 minSize) external onlyOwner {
        minimumPositionSize[token] = minSize;
        emit MinimumPositionSizeSet(token, minSize);
    }

    /// @notice Donate a single NFT to be used as a reward
    /// @param erc721 The ERC721 contract address
    /// @param tokenId The token ID to donate
    /// TODO: Either gate this function or have a list of approved NFTs that can be donated
    /// to avoid spamming the contract with random NFTs.
    function donate(address erc721, uint256 tokenId) external {
        _donate(erc721, tokenId);
    }

    /// @notice Donate multiple NFTs to be used as rewards
    /// @param erc721s Array of ERC721 contract addresses
    /// @param tokenIds Array of token IDs to donate
    /// TODO: Either gate this function or have a list of approved NFTs that can be donated
    /// to avoid spamming the contract with random NFTs.
    function donateBatch(address[] calldata erc721s, uint256[] calldata tokenIds) external {
        if (erc721s.length != tokenIds.length) {
            revert ArrayLengthMismatch();
        }
        for (uint256 i = 0; i < erc721s.length; i++) {
            _donate(erc721s[i], tokenIds[i]);
        }
    }

    function _donate(address erc721, uint256 tokenId) internal {
        uint256 newRewardIndex = rewards.length;
        rewards.push(ERC721Reward({erc721: erc721, tokenId: tokenId, claimed: false}));
        unclaimedRewardIndices.push(newRewardIndex);
        IERC721(erc721).transferFrom(msg.sender, address(this), tokenId);
        emit Donated(msg.sender, erc721, tokenId);
    }

    /// @notice Claim AAVE position after cooldown period
    /// @dev Transfers aTokens to the user if cooldown period has passed
    /// @param token The underlying token address
    function claimAavePosition(address token) external {
        MigrationRequest storage request = requests[msg.sender][token];

        // Check cooldown period
        if (block.timestamp < request.timestamp + COOLDOWN_PERIOD) {
            revert CooldownActive();
        }

        // Get the aToken address
        address aToken = IPool(AAVE_POOL).getReserveData(token).aTokenAddress;
        if (aToken == address(0)) {
            revert TokenNotSupported(token);
        }

        // Transfer aTokens to user
        uint256 amount = request.amount;
        request.amount = 0; // Clear position before transfer
        IERC20(aToken).safeTransfer(msg.sender, amount);
    }

    function migratePosition(address token, uint256 amount) external nonReentrant {
        if (unclaimedRewardIndices.length == 0) {
            revert NoRewardsAvailable();
        }

        uint256 minSize = minimumPositionSize[token];
        if (minSize == 0) {
            revert TokenNotSupported(token);
        }
        if (amount < minSize) {
            revert PositionTooSmall(token, amount, minSize);
        }

        MigrationRequest storage request = requests[msg.sender][token];
        if (request.hasClaimedReward) {
            revert RewardAlreadyClaimed();
        }
        request.timestamp = block.timestamp;

        // Transfer tokens and open AAVE position
        (address underlyingToken, uint256 underlyingAmount) =
            transferTokensForMigration(token, amount);
        // slither-disable-next-line reentrancy-no-eth
        request.amount = openAavePosition(underlyingToken, underlyingAmount);

        // Request randomness to oracle to select a reward
        //slither-disable-next-line reentrancy-no-eth
        uint256 requestId = VRF_COORDINATOR.requestRandomWords(
            KEY_HASH, SUBSCRIPTION_ID, REQUEST_CONFIRMATIONS, CALLBACK_GAS_LIMIT, NUM_WORDS
        );
        request.requestId = requestId;
        positions[requestId] = Position({user: msg.sender, token: token});
    }

    /// @notice Transfer tokens from user to this contract
    /// @dev Must be implemented by the contract that uses this contract
    /// @param token The token address
    /// @param amount The amount of tokens to transfer
    function transferTokensForMigration(address token, uint256 amount)
        internal
        virtual
        returns (address underlyingToken, uint256 underlyingAmount)
    {
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
        return (token, amount);
    }

    /// @notice Open a position in AAVE v3 with the provided tokens
    /// @dev Transfers tokens from user, supplies to AAVE, and starts cooldown period
    /// @param token The underlying token to supply
    /// @param amount The amount of tokens to supply
    function openAavePosition(address token, uint256 amount) internal returns (uint256) {
        // Get the aToken address
        address aToken = IPool(AAVE_POOL).getReserveData(token).aTokenAddress;
        if (aToken == address(0)) {
            revert TokenNotSupported(token);
        }

        // Approve AAVE pool to spend tokens
        if (!IERC20(token).approve(AAVE_POOL, amount)) {
            revert ApproveFailed();
        }

        // Check aToken balance before supply
        uint256 aTokenBalanceBefore = IAToken(aToken).balanceOf(address(this));

        // Supply tokens to AAVE
        IPool(AAVE_POOL).supply(
            token,
            amount,
            address(this), // We keep the aTokens until COOLDOWN_PERIOD passes to avoid cycle attacks
            AAVE_REFERRAL_CODE
        );

        // Check aToken balance after supply - the difference need to be tracked for the user
        uint256 aTokenBalanceAfter = IAToken(aToken).balanceOf(address(this));
        return aTokenBalanceAfter - aTokenBalanceBefore;
    }

    /// @notice Callback function used by VRF Coordinator
    /// @dev Selects and transfers a random NFT to the user
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        Position memory position = positions[requestId];
        if (position.user == address(0)) {
            revert InvalidRequestId();
        }
        MigrationRequest storage request = requests[position.user][position.token];
        if (request.requestId != requestId) {
            revert RequestIdMismatch();
        }
        if (request.hasClaimedReward) {
            revert RewardAlreadyClaimed();
        }

        // Update request state
        request.hasClaimedReward = true;

        // Get the randomly selected NFT to transfer to user
        ERC721Reward memory reward = getReward(randomWords);
        IERC721(reward.erc721).transferFrom(address(this), position.user, reward.tokenId);
        emit Claimed(position.user, reward.erc721, reward.tokenId);
    }

    /// @notice Helper function to get a reward at a specific index
    /// @dev Uses the unclaimedRewardIndices array for O(1) access
    /// @param randomWords The random words from the VRF request
    /// @return reward The selected reward
    function getReward(uint256[] memory randomWords) private returns (ERC721Reward memory reward) {
        if (unclaimedRewardIndices.length == 0) {
            revert NoRewardsAvailable();
        }

        // Select a random index from the unclaimedRewardIndices array
        uint256 selectedUnclaimedIndex = randomWords[0] % unclaimedRewardIndices.length;
        uint256 rewardIndex = unclaimedRewardIndices[selectedUnclaimedIndex];
        // TODO: Require not needed if we ensure the invariant that rewards in unclaimedRewardIndices are never claimed
        if (rewards[rewardIndex].claimed) {
            revert RewardAlreadyClaimed();
        }
        rewards[rewardIndex].claimed = true;
        reward = rewards[rewardIndex];

        // Remove the claimed reward index by swapping with the last element and popping
        if (selectedUnclaimedIndex != unclaimedRewardIndices.length - 1) {
            uint256 lastUnclaimedIndex = unclaimedRewardIndices[unclaimedRewardIndices.length - 1];
            unclaimedRewardIndices[selectedUnclaimedIndex] = lastUnclaimedIndex;
        }
        unclaimedRewardIndices.pop();
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
