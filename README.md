# sol-template

[![Build](https://github.com/0xmichalis/sol-template/actions/workflows/build.yml/badge.svg)](https://github.com/0xmichalis/sol-template/actions/workflows/build.yml) [![Tests](https://github.com/0xmichalis/sol-template/actions/workflows/test.yml/badge.svg)](https://github.com/0xmichalis/sol-template/actions/workflows/test.yml) [![Lint](https://github.com/0xmichalis/sol-template/actions/workflows/lint.yml/badge.svg)](https://github.com/0xmichalis/sol-template/actions/workflows/lint.yml) [![Static analysis](https://github.com/0xmichalis/sol-template/actions/workflows/analyze.yml/badge.svg)](https://github.com/0xmichalis/sol-template/actions/workflows/analyze.yml)

Barebones template to get started with Solidity projects.

## Install

```sh
git clone https://github.com/0xmichalis/sol-template.git
cd sol-template
forge install
```

## Build

```sh
forge build
```

## Test

```sh
forge test
```

## Update Gas Snapshot

```sh
forge snapshot
```

## Test in forked network

```console
cp .env.example .env
# Update .env with your values
# Then, source the environment file
source .env
# Run tests
FORK_MODE=true forge test \
  --fork-url $FORK_URL \
  -vvv
```
