// Strategy A - counterfactual pre-funding, then DEPLOY_ACCOUNT paid by the new wallet itself.
//
//   node counterfactual.mjs
//
// 1. new key pair -> constructor calldata + salt
// 2. compute the address the account WILL have
// 3. funder transfers STRK to that empty address
// 4. the new account signs DEPLOY_ACCOUNT; validation finds the balance, the fee is paid from it
import { Account, CallData, ec, stark } from "starknet";
import { ACCOUNT_CLASS_HASH, FUND_AMOUNT, counterfactualAddress, fmt, funder, hex, provider, strkBalance, strkTransferCall } from "./common.mjs";

const p = provider();
const payer = funder(p);

const privateKey = stark.randomAddress();
const publicKey = ec.starkCurve.getStarkKey(privateKey);
const constructorCalldata = CallData.compile({ publicKey });
const salt = publicKey;
const address = counterfactualAddress(ACCOUNT_CLASS_HASH, constructorCalldata, salt);

console.log("new account private key (testnet only):", privateKey);
console.log("future address                       :", address);
console.log("balance before funding               :", fmt(await strkBalance(p, address)));

// 3. fund the address that has no code yet
const fund = await payer.execute(strkTransferCall(address, FUND_AMOUNT));
console.log("funding tx:", fund.transaction_hash);
await p.waitForTransaction(fund.transaction_hash);
console.log("balance after funding                :", fmt(await strkBalance(p, address)));

// 4. deploy the account - the fee comes out of the balance we just sent
const fresh = new Account(p, address, privateKey);
const fee = await fresh.estimateAccountDeployFee({ classHash: ACCOUNT_CLASS_HASH, constructorCalldata, addressSalt: salt });
console.log("estimated deploy fee                 :", fmt(fee.overall_fee));
const deploy = await fresh.deployAccount({ classHash: ACCOUNT_CLASS_HASH, constructorCalldata, addressSalt: salt });
console.log("DEPLOY_ACCOUNT tx:", deploy.transaction_hash);
await p.waitForTransaction(deploy.transaction_hash);

if (hex(deploy.contract_address) !== hex(address)) throw new Error("address mismatch - check class hash / calldata");
console.log("deployed at                          :", deploy.contract_address);
console.log("balance after deployment             :", fmt(await strkBalance(p, address)));
console.log("the wallet paid its own deployment from the STRK it received before it existed.");
