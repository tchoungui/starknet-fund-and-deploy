use fund_and_deploy::mocks::{
    IMockAccountDispatcher, IMockAccountDispatcherTrait, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
};
use fund_and_deploy::{
    IAccountFactoryDispatcher, IAccountFactoryDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

const FUND: u256 = 250_000;

fn setup() -> (ContractAddress, ContractAddress, starknet::ClassHash, ContractAddress) {
    let token_class = declare("MockERC20").unwrap().contract_class();
    let (token, _) = token_class.deploy(@array![]).unwrap();
    let factory_class = declare("AccountFactory").unwrap().contract_class();
    let (factory, _) = factory_class.deploy(@array![token.into()]).unwrap();
    let account_class = declare("MockAccount").unwrap().contract_class();
    let funder: ContractAddress = 0xF00D.try_into().unwrap();
    IMockERC20Dispatcher { contract_address: token }.mint(funder, 1_000_000);
    (token, factory, *account_class.class_hash, funder)
}

#[test]
fn one_call_deploys_and_funds_the_account() {
    let (token, factory, account_class, funder) = setup();
    let erc20 = IERC20Dispatcher { contract_address: token };

    // the funder approves the factory (in the real world: first call of the multicall)
    start_cheat_caller_address(token, funder);
    erc20.approve(factory, FUND);
    stop_cheat_caller_address(token);

    // ... and calls fund_and_deploy (second call of the same multicall)
    start_cheat_caller_address(factory, funder);
    let account = IAccountFactoryDispatcher { contract_address: factory }
        .fund_and_deploy(account_class, 0x1234, array![0xAB].span(), FUND);
    stop_cheat_caller_address(factory);

    // deployed: the constructor ran with our calldata
    assert(IMockAccountDispatcher { contract_address: account }.public_key() == 0xAB, 'not deployed');
    // funded: the balance moved from the funder to the brand-new account in the same call
    assert(erc20.balance_of(account) == FUND, 'account not funded');
    assert(erc20.balance_of(funder) == 1_000_000 - FUND, 'funder not debited');
    assert(erc20.allowance(funder, factory) == 0, 'allowance not consumed');
    assert(IAccountFactoryDispatcher { contract_address: factory }.fee_token() == token, 'fee token');
}

#[test]
fn same_inputs_give_same_address_only_once() {
    let (token, factory, account_class, funder) = setup();
    start_cheat_caller_address(token, funder);
    IERC20Dispatcher { contract_address: token }.approve(factory, FUND * 2);
    stop_cheat_caller_address(token);
    start_cheat_caller_address(factory, funder);
    let dispatcher = IAccountFactoryDispatcher { contract_address: factory };
    let a = dispatcher.fund_and_deploy(account_class, 0x1, array![0x1].span(), FUND);
    let b = dispatcher.fund_and_deploy(account_class, 0x2, array![0x1].span(), FUND);
    stop_cheat_caller_address(factory);
    assert(a != b, 'salt must change the address');
}

#[test]
#[should_panic]
fn redeploying_the_same_address_fails() {
    let (_token, factory, account_class, funder) = setup();
    start_cheat_caller_address(factory, funder);
    let dispatcher = IAccountFactoryDispatcher { contract_address: factory };
    dispatcher.fund_and_deploy(account_class, 0x7, array![0x9].span(), 0);
    dispatcher.fund_and_deploy(account_class, 0x7, array![0x9].span(), 0); // address already taken
}

#[test]
#[should_panic(expected: 'INSUFFICIENT_ALLOWANCE')]
fn funding_without_allowance_reverts_the_whole_call() {
    let (_token, factory, account_class, funder) = setup();
    start_cheat_caller_address(factory, funder);
    IAccountFactoryDispatcher { contract_address: factory }
        .fund_and_deploy(account_class, 0x42, array![0x1].span(), FUND);
}
