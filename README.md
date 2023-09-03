## Proba

Proba is a Web3 Protocol for building and interacting with decentralized games of chance powered by
randomly executable NFTs (rxNFTs).

At its core, Proba Protocol is an open-source suite of smart contracts that enables anyone to build
decentralized games of chance on the blockchain. It provides a framework for creating and
interacting with games through minting and executing NFTs called rxNFTs.

rxNFTs are programmable ERC-721 tokens that grant their holder ownership rights over the execution
of verifiable random on-chain code that can represent lottery, loot boxes, casino games, and other
games of chance.

### Games

The initial version of Proba will consists of 3 games.

#### Competition

A lottery where users can buy rxNFT tickets to win a reward. Each ticket grants an equal chance of
winning, which are bought with either native or ERC20 tokens determined at competition creation
time. Draws are conducted via Chainlink VRF.

The remaining games are T.B.D.

## Documentation

## Development

### Build

```shell
$ forge build --sizes
```

### Test

```shell
$ forge test
```

Use `-v` liberally for traces, e.g. `-vvvv`

### Docs

```shell
$ forge doc
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

First, compile with `--via-ir` so that the contracts are optimized. This saves gas both for
deployment and execution.

Provide in environment variables at minimum the deployment private key (with leading 0x) and node
URL. If you use `env.template` as a template you can source it with e.g. `source .env`

Run deploy script:

```shell
forge script script/ProbaCompetition.s.sol:DeployProbaCompFactory --rpc-url $ETH_NODE_GOERLI_URL --broadcast -vvvv
```

#### Verification

Edit `foundry.toml` in the `[etherscan]` section and add API key to environment variables, then
run deploy script with `--verify`.

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
