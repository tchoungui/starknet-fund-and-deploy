// Strategy B - ONE transaction from a funded deployer: approve STRK, then factory.fund_and_deploy(...).
//
//   node factory.mjs        (needs FACTORY_ADDRESS from deploy-factory.mjs)
//
// The deployer pays the gas of this single multicall. The new wallet comes to life already holding FUND_AMOUNT
// and, thanks to deploy_from_zero, at the exact address DEPLOY_ACCOUNT would have given it.
import { CallData, ec, stark, uint256 } from "starknet";
import { ACCOUNT_CLASS_HASH, FUND_AMOUNT, counterfactualAddress, env, fmt, funder, hex, provider, strkApproveCall, strkBalance } from "./common.mjs";

const p = provider();
const payer = funder(p);
const factory = env("FACTORY_ADDRESS");

const privateKey = stark.randomAddress();
const publicKey = ec.starkCurve.getStarkKey(privateKey);
const constructorCalldata = CallData.compile({ publicKey });
const salt = publicKey;
const expected = counterfactualAddress(ACCOUNT_CLASS_HASH, constructorCalldata, salt);

console.log("new account private key (testnet only):", privateKey);
console.log("expected address                     :", expected);

const calls = [
  strkApproveCall(factory, FUND_AMOUNT),
  {
    contractAddress: factory,
    entrypoint: "fund_and_deploy",
    calldata: CallData.compile({
      class_hash: ACCOUNT_CLASS_HASH,
      salt,
      constructor_calldata: constructorCalldata,
      amount: uint256.bnToUint256(FUND_AMOUNT),
    }),
  },
];

const tx = await payer.execute(calls);
console.log("single multicall tx:", tx.transaction_hash);
const receipt = await p.waitForTransaction(tx.transaction_hash);

// the factory emits AccountFundedAndDeployed(account, class_hash, salt, amount, funder); `account` is a key
const ev = (receipt.events || []).find((e) => hex(e.from_address) === hex(factory));
const deployedAt = ev ? hex(ev.keys[1]) : "(event not found)";
console.log("factory says deployed at             :", deployedAt);
if (ev && deployedAt !== hex(expected)) throw new Error("address mismatch - deploy_from_zero broken?");

const code = await p.getClassHashAt(expected).catch(() => null);
console.log("class hash at address                :", code ? hex(code) : "none");
console.log("balance of the brand-new wallet      :", fmt(await strkBalance(p, expected)));
console.log("deployed and funded in one transaction; the wallet never needed gas of its own.");
