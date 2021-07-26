address 0x1 {

/// The `Genesis` module defines the Move initialization entry point of the Diem framework
/// when executing from a fresh state.
///
/// > TODO: Currently there are a few additional functions called from Rust during genesis.
/// > Document which these are and in which order they are called.
module Genesis {
    use 0x1::ChainId;
    use 0x1::DiemAccount;
    use 0x1::PONT;

    /// Initializes the Diem framework.
    fun initialize(
        dr_account: signer,
        tc_account: signer,
        dr_auth_key: vector<u8>,
        tc_auth_key: vector<u8>,
        chain_id: u8,
    ) {
        let dr_account = &dr_account;
        let tc_account = &tc_account;

        DiemAccount::initialize(dr_account, x"");

        ChainId::initialize(dr_account, chain_id);

        // Currency setup
        PONT::initialize(dr_account, tc_account);

        let dr_rotate_key_cap = DiemAccount::extract_key_rotation_capability(dr_account);
        DiemAccount::rotate_authentication_key(&dr_rotate_key_cap, dr_auth_key);
        DiemAccount::restore_key_rotation_capability(dr_rotate_key_cap);

        let tc_rotate_key_cap = DiemAccount::extract_key_rotation_capability(tc_account);
        DiemAccount::rotate_authentication_key(&tc_rotate_key_cap, tc_auth_key);
        DiemAccount::restore_key_rotation_capability(tc_rotate_key_cap);
    }
}
}
