%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import (assert_le, assert_nn_le, unsigned_div_rem)
from starkware.starknet.common.syscalls import (get_caller_address, storage_read, storage_write)

// the maximum amount of each token that belongs to the AMM
const BALANCE_UPPER_BOUND = 2 ** 64;

const TOKEN_TYPE_A = 1;
const TOKEN_TYPE_B = 2;

// Ensure the user's balances are much smaller than the pool's balance
const POOL_UPPER_BOUND = 2 ** 30;
const ACCOUNT_BALANCE_BOUND = 1073741; // (2 ** 30 / 1000)

// A map from account and token type to corresponding balance
@storage_var
func account_balance(account_id: felt, token_type: felt) -> (balance: felt) {
}

// a map from token type to corresponding pool balance
@storage_var
func pool_balance(token_type: felt) -> (balance: felt) {
}


// updates account balance for a given token
func modify_account_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account_id: felt, token_type: felt, amount: felt
) {
    let (current_balance) = account_balance.read(account_id, token_type);
    tempvar new_balance = current_balance + amount;

    with_attr error_message("exceeds maximum allowed tokens!"){
        assert_nn_le(new_balance, BALANCE_UPPER_BOUND - 1);
    }

    account_balance.write(account_id=account_id, token_type=token_type, value=new_balance);
    return ();
}

// returns account balance for a given token
@view
func get_account_token_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account_id: felt, token_type: felt
) -> (balance: felt) {
    return account_balance.read(account_id, token_type);
}

// set pool balance for a given token
@view
func set_pool_token_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_type: felt, balance: felt
) {
    with_attr error_message("exceeds maximum allowed tokens!"){
        assert_nn_le(balance, BALANCE_UPPER_BOUND - 1);
    }

    pool_balance.write(token_type, balance);
    return ();
}

// return the pool's balance
@view
func get_pool_token_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_type: felt
) -> (balance: felt) {
    return pool_balance.read(token_type);
}

// swaps tokens between the given account and the pool
func do_swap{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account_id: felt, token_from: felt, token_to: felt, amount_from: felt
) -> (amount_to: felt) {
    alloc_locals;

    // get pool balance
    let (local amm_from_balance) = get_pool_token_balance(token_type = token_from);
    let (local amm_to_balance) = get_pool_token_balance(token_type=token_to);

    // calculate swap amount
    let (local amount_to, _) = unsigned_div_rem((amm_to_balance * amount_from), (amm_from_balance + amount_from));

    // update token_from balances
    modify_account_balance(account_id=account_id, token_type=token_from, amount=-amount_from);
    set_pool_token_balance(token_type=token_from, balance=(amm_from_balance + amount_from));

    // update token_to balances
    modify_account_balance(account_id=account_id, token_type=token_to, amount=amount_to);
    set_pool_token_balance(token_type=token_to, balance=(amm_to_balance - amount_to));

    return (amount_to=amount_to);
}

func get_opposite_token(token_type: felt) -> (t: felt) {
    if(token_type == TOKEN_TYPE_A) {
        return (t=TOKEN_TYPE_B);
    } else {
        return (t=TOKEN_TYPE_A);
    }
}

// swaps token between the given account and the pool
@external
func swap{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_from: felt, amount_from: felt
) -> (amount_to: felt) {
    let (account_id) = get_caller_address();

    // verify token_from is TOKEN_TYPE_A or TOKEN_TYPE_B
    with_attr error_message("token not allowed in pool!"){
        assert (token_from - TOKEN_TYPE_A) * (token_from - TOKEN_TYPE_B) = 0;
    }

    // check requested amount_from is valid
    with_attr error_message("exceeds maximum allowed tokens!"){
        assert_nn_le(amount_from, BALANCE_UPPER_BOUND - 1);
    }

    // check user has enough funds
    let (account_from_balance) = get_account_token_balance(account_id=account_id, token_type=token_from);
    with_attr error_message("insufficient balance!"){
        assert_le(amount_from, account_from_balance);
    }

    let (token_to) = get_opposite_token(token_type=token_from);
    let (amount_to) = do_swap(account_id=account_id, token_from=token_from, token_to=token_to, amount_from=amount_from);

    return (amount_to=amount_to);
}

// add demo token to the given account
@external
func add_demo_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_a_amount: felt, token_b_amount: felt
) {
    let (account_id) = get_caller_address();

    modify_account_balance(account_id=account_id, token_type=TOKEN_TYPE_A, amount=token_a_amount);
    modify_account_balance(account_id=account_id, token_type=TOKEN_TYPE_B, amount=token_b_amount);

    return ();
}

//  intialize AMM
@external
func init_pool{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_a: felt, token_b: felt
) {
    with_attr error_message("exceeds maximum allowed tokens!"){
        assert_nn_le(token_a, POOL_UPPER_BOUND - 1);
        assert_nn_le(token_b, POOL_UPPER_BOUND - 1);
    }

    set_pool_token_balance(token_type=TOKEN_TYPE_A, balance=token_a);
    set_pool_token_balance(token_type=TOKEN_TYPE_B, balance=token_b);

    return ();
}