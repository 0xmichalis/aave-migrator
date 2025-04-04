# AAVE Migrator

[![Build](https://github.com/0xmichalis/aave-migrator/actions/workflows/build.yml/badge.svg)](https://github.com/
0xmichalis/aave-migrator/actions/workflows/build.yml) [![Tests](https://github.com/0xmichalis/aave-migrator/actions/
workflows/test.yml/badge.svg)](https://github.com/0xmichalis/aave-migrator/actions/workflows/test.yml) [![Lint](https://
github.com/0xmichalis/aave-migrator/actions/workflows/lint.yml/badge.svg)](https://github.com/0xmichalis/aave-migrator/
actions/workflows/lint.yml) [![Static analysis](https://github.com/0xmichalis/aave-migrator/actions/workflows/analyze.yml/
badge.svg)](https://github.com/0xmichalis/aave-migrator/actions/workflows/analyze.yml)

A smart contract system that allows users to migrate their tokens to AAVE v3 and receive NFT rewards for doing so.

## Overview

This project implements a token migration system with NFT rewards. Users can:
1. Deposit tokens into AAVE v3 pools
2. Receive NFT rewards for their participation
3. Claim their positions after a cooldown period

The system uses Chainlink VRF for fair NFT distribution and integrates with AAVE v3 for yield generation. 

The cooldown period is implemented as a security measure to avoid cycle attacks. Otherwise, a user could deposit into AAVE through the contract, withdraw from AAVE, move the funds to a different account and repeat the process until they can claim all NFTs from the contract.

## Features

- **AAVE v3 Integration**: Deposit tokens into AAVE v3 pools to earn yield
- **NFT Rewards**: Receive NFT rewards for participating in the migration
- **Chainlink VRF**: Fair and verifiable random NFT distribution

### TODO

- **NFT Allowlist**: Allowlist NFTs that can be donated to avoid giving out spam as rewards
- **Tests for CompoundV3Migrator.sol**: Currently missing

## Architecture

### Core Components

1. **Migrator.sol**
   - Main contract handling token deposits and NFT rewards
   - Integrates with AAVE v3 and Chainlink VRF
   - Manages cooldown periods and position tracking

2. **CompoundV3Migrator.sol**
   - Extension of `Migrator` that incentivizes migrations from Compound v3

### Key Mechanisms

1. **Token Migration**
   ```solidity
   function migratePosition(address token, uint256 amount)
   ```
   - Transfers user tokens to AAVE v3
   - Stores position details with normalized income
   - Triggers VRF for NFT reward selection

2. **Position Claiming**
   ```solidity
   function claimAavePosition(address token)
   ```
   - Verifies cooldown period has passed
   - Calculates earned interest using normalized income
   - Transfers aTokens back to user

3. **NFT Donations**
   ```solidity
   function donate(address nft, uint256 tokenId)
   ```
   - Allows adding NFTs as rewards
   - Randomly distributed to migrators via Chainlink VRF

## Development

### Installation

```sh
# Clone the repository
git clone https://github.com/0xmichalis/aave-migrator.git
cd aave-migrator

# Install dependencies
forge install
```

### Testing locally

```sh
forge test
```

### Testing on a forked network

```sh
cp .env.example .env
# Update .env with your values
# Then, source the environment file
source .env
# Run tests
FORK_MODE=true forge test \
  --fork-url $FORK_URL \
  -vvv
```

## License

MIT
