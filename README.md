# Starknet: fund a wallet *while* deploying it

On Starknet every wallet is a smart contract. A fresh account therefore faces a chicken-and-egg problem:

* the account does not exist on chain until a `DEPLOY_ACCOUNT` transaction runs,
* that transaction pays a fee in STRK,
* the fee is charged to the account being deployed, which has no balance yet.

If you just sign `DEPLOY_ACCOUNT` from an empty address the sequencer rejects it at validation
(`Insufficient balance` / `Max fee exceeds balance`). This repository shows the three ways out, with working
code for the two you can run yourself on **Sepolia**.

| Strategy | Who pays gas | Transactions | When to use |
|---|---|---|---|
| **A. Counterfactual pre-funding** | the new account (from the STRK it received) | 2 (transfer, then `DEPLOY_ACCOUNT`) | the standard wallet flow (Argent, Braavos, OpenZeppelin) |
| **B. Factory: fund + deploy in one call** | a funded "deployer" account | 1 multicall | onboarding many users, treasuries, bots, testnet tooling |
| **C. Paymaster (sponsored deployment)** | a paymaster service | 1, signed by the user | consumer apps that hide gas entirely (SNIP-29, AVNU, Cartridge) |

The trick that makes **B** identical to **A** for the resulting wallet: the factory deploys with
`deploy_from_zero = true`, so the address is computed with `deployer_address = 0`, the same formula
`DEPLOY_ACCOUNT` uses. The wallet software can later derive the very same address from the key, class hash and salt.

## Repository layout

```
contracts/            Cairo package `fund_and_deploy` (Scarb 2.20 + Starknet Foundry 0.63)
  src/lib.cairo       AccountFactory.fund_and_deploy(class_hash, salt, calldata, amount)
  src/mocks.cairo     MockAccount + MockERC20 used by the tests
  tests/              snforge: one call -> deployed AND funded; factory address == DEPLOY_ACCOUNT address
scripts/              starknet.js (v7) demos against Sepolia
  counterfactual.mjs  Strategy A: compute address -> transfer STRK -> DEPLOY_ACCOUNT
  factory.mjs         Strategy B: approve + fund_and_deploy in ONE multicall
  deploy-factory.mjs  declare + deploy the factory once
.github/workflows/    scarb build + snforge test + node syntax check on every push
```

## How the address is known before deployment

```
address = pedersen(
    "STARKNET_CONTRACT_ADDRESS",
    deployer_address,           # 0 for DEPLOY_ACCOUNT and for deploy_from_zero
    salt,                       # wallets use the public key
    class_hash,                 # the account implementation
    pedersen(constructor_calldata)
) mod 2**251
```

starknet.js: `hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0)`.
Cairo: `deploy_syscall(class_hash, salt, calldata, deploy_from_zero: true)` returns exactly that address.

## Strategy A - counterfactual pre-funding (`scripts/counterfactual.mjs`)

1. Generate a key pair, build the constructor calldata (`public_key` for the OpenZeppelin account), salt = public key.
2. Compute the future address off-chain.
3. From a funded account, `transfer` STRK to that address. The chain happily credits an address that has no code yet.
4. Sign `DEPLOY_ACCOUNT` with the new key. Validation now finds the balance; the fee is paid from it.

## Strategy B - one transaction (`contracts/src/lib.cairo` + `scripts/factory.mjs`)

```cairo
fn fund_and_deploy(ref self, class_hash, salt, constructor_calldata, amount) -> ContractAddress {
    let funder = get_caller_address();
    let (account, _) = deploy_syscall(class_hash, salt, constructor_calldata, true).unwrap_syscall();
    if amount > 0 {
        assert(IERC20Dispatcher { contract_address: self.fee_token.read() }
            .transfer_from(funder, account, amount), 'FUND_TRANSFER_FAILED');
    }
    self.emit(AccountFundedAndDeployed { account, class_hash, salt, amount, funder });
    account
}
```

The deployer account sends **one** multicall: `STRK.approve(factory, amount)` then
`factory.fund_and_deploy(...)`. The deployer pays the fee of that transaction; the new wallet is born
with `amount` STRK already in it and can send its first transaction immediately.

Caveats worth knowing:

* The account's constructor runs, but its `__validate_deploy__` does not (that hook only exists for
  `DEPLOY_ACCOUNT`). For OpenZeppelin / Argent / Braavos classes this is fine; check your class if it relies on it.
* The factory never holds funds: it moves STRK with `transfer_from` under an allowance granted in the same multicall.
* Anyone can call the factory. That is intended; the funder only ever spends its own approved amount.

## Strategy C - paymaster

With SNIP-29 paymasters (AVNU, Cartridge) the user signs a typed-data message that includes the deployment data;
the paymaster submits `DEPLOY_ACCOUNT` and pays in the token of its choice. starknet.js exposes this as
`account.executePaymasterTransaction(...)` with `deploymentData`. No code here because it depends on the
provider's API key; the README of the paymaster you pick has the two calls you need.

## Run it

```bash
# contracts
cd contracts
scarb build
snforge test

# scripts (Sepolia)
cd ../scripts
npm install
cp .env.example .env         # RPC URL, funder address + private key, class hashes
node deploy-factory.mjs      # once; prints FACTORY_ADDRESS -> put it in .env
node counterfactual.mjs      # strategy A
node factory.mjs             # strategy B
```

Sepolia STRK: `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`.
Fund the deployer at <https://starknet-faucet.vercel.app>. Testnet only; never reuse these keys on mainnet.

## Security notes

* Keys in the demo are generated per run and printed to the console. Store real keys in a wallet or an HSM.
* Fund with the minimum that covers a few transactions; the factory takes the exact `amount` you approve.
* Verify class hashes against the wallet vendor's release notes before deploying user accounts.

---

Written by **Nabil Tchoungui**, Web3 & Blockchain Engineering agent of the 101RE AgentX studio
(<https://my-agentx101.tokenomy.world>). MIT licence.
