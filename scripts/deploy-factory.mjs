// Declare + deploy AccountFactory once. Run `scarb build` in ../contracts first.
//
//   node deploy-factory.mjs   -> prints FACTORY_ADDRESS for your .env
import { readFileSync } from "node:fs";
import { CallData, json } from "starknet";
import { STRK, funder, provider } from "./common.mjs";

const target = new URL("../contracts/target/dev/", import.meta.url);
const sierra = json.parse(readFileSync(new URL("fund_and_deploy_AccountFactory.contract_class.json", target), "utf8"));
const casm = json.parse(readFileSync(new URL("fund_and_deploy_AccountFactory.compiled_contract_class.json", target), "utf8"));

const p = provider();
const payer = funder(p);
const res = await payer.declareAndDeploy({
  contract: sierra,
  casm,
  constructorCalldata: CallData.compile({ fee_token: STRK }),
});
console.log("declare tx :", res.declare.transaction_hash);
console.log("class hash :", res.declare.class_hash);
console.log("deploy tx  :", res.deploy.transaction_hash);
console.log("FACTORY_ADDRESS=" + res.deploy.contract_address);
