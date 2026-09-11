//! Test doubles: a minimal account (stores a public key) and a mintable ERC20 standing in for STRK.
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockAccount<TState> {
    fn public_key(self: @TState) -> felt252;
}

#[starknet::interface]
pub trait IMockERC20<TState> {
    fn mint(ref self: TState, to: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod MockAccount {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        public_key: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
        self.public_key.write(public_key);
    }

    #[abi(embed_v0)]
    impl MockAccountImpl of super::IMockAccount<ContractState> {
        fn public_key(self: @ContractState) -> felt252 {
            self.public_key.read()
        }
    }
}

#[starknet::contract]
pub mod MockERC20 {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
    }

    #[abi(embed_v0)]
    impl MockImpl of super::IMockERC20<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.balances.write(to, self.balances.read(to) + amount);
        }
    }

    #[abi(embed_v0)]
    impl ERC20Impl of crate::IERC20<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.allowances.write((get_caller_address(), spender), amount);
            true
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let from = get_caller_address();
            self._move(from, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
        ) -> bool {
            let spender = get_caller_address();
            let allowed = self.allowances.read((sender, spender));
            assert(allowed >= amount, 'INSUFFICIENT_ALLOWANCE');
            self.allowances.write((sender, spender), allowed - amount);
            self._move(sender, recipient, amount);
            true
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn _move(ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256) {
            let bal = self.balances.read(from);
            assert(bal >= amount, 'INSUFFICIENT_BALANCE');
            self.balances.write(from, bal - amount);
            self.balances.write(to, self.balances.read(to) + amount);
        }
    }
}
