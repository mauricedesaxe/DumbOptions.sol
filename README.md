## DumbOptions.sol

**DumbOptions.sol is a simple protocol for creating and trading options.**

## Future goals

- [ ] Write a full testing suite for `Option.sol` covering all possible errors and edge cases
- [ ] Add forked mainnet support for testing with real Chainlink price feeds 

## Future ideas

- [ ] Add a UI for creating and trading options for any asset that has a Chainlink price feed
- [ ] Make options fungible and tradeable once initial option sale happens
- [ ] Consider automation of settlement (at strike price or expiration) 
- [ ] Consider multi-chain deployment with cross-chain bridges & trading

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
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

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

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
