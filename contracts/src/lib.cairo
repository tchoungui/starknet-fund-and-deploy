//! Fund a Starknet account contract in the same transaction that deploys it.
//!
//! `deploy_syscall(..., deploy_from_zero: true)` gives the address that a `DEPLOY_ACCOUNT` transaction would
//! have produced (deployer address = 0), so the resulting wallet is indistinguishable from a self-deployed one.
pub mod mocks;

use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
pub trait IERC20<TState> {
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
}

#[starknet::interface]
pub trait IAccountFactory<TState> {
    /// Deploys `class_hash` at the counterfactual address derived from (0, salt, class_hash, calldata) and
    /// moves `amount` of the fee token from the caller to that address. Returns the new account address.
    fn fund_and_deploy(
        ref self: TState,
        class_hash: ClassHash,
        salt: felt252,
        constructor_calldata: Span<felt252>,
        amount: u256,
    ) -> ContractAddress;
    fn fee_token(self: @TState) -> ContractAddress;
}

#[starknet::contract]
pub mod AccountFactory {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        fee_token: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        AccountFundedAndDeployed: AccountFundedAndDeployed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AccountFundedAndDeployed {
        #[key]
        pub account: ContractAddress,
        pub class_hash: ClassHash,
        pub salt: felt252,
        pub amount: u256,
        pub funder: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, fee_token: ContractAddress) {
        self.fee_token.write(fee_token);
    }

    #[abi(embed_v0)]
    impl AccountFactoryImpl of super::IAccountFactory<ContractState> {
        fn fund_and_deploy(
            ref self: ContractState,
            class_hash: ClassHash,
            salt: felt252,
            constructor_calldata: Span<felt252>,
            amount: u256,
        ) -> ContractAddress {
            let funder = get_caller_address();
            // deploy_from_zero = true -> address independent of this factory, equal to the DEPLOY_ACCOUNT address.
            let (account, _) = deploy_syscall(class_hash, salt, constructor_calldata, true)
                .unwrap_syscall();
            if amount > 0 {
                let token = IERC20Dispatcher { contract_address: self.fee_token.read() };
                let ok = token.transfer_from(funder, account, amount);
                assert(ok, 'FUND_TRANSFER_FAILED');
            }
            self.emit(AccountFundedAndDeployed { account, class_hash, salt, amount, funder });
            account
        }

        fn fee_token(self: @ContractState) -> ContractAddress {
            self.fee_token.read()
        }
    }
}
