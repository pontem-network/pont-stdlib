address 0x1 {

/// KUSD (Kusama USD) Coin.
module KUSD {
    use 0x1::AccountLimits;
    use 0x1::CoreAddresses;
    use 0x1::FixedPoint32;
    use 0x1::Diem;
    use 0x1::DiemTimestamp;

    struct KUSD has key, store {}

    struct Drop has key {
        mint_cap: Diem::MintCapability<KUSD>,
        burn_cap: Diem::BurnCapability<KUSD>,
    }

    /// Registers the `KSM` cointype. This can only be called from genesis.
    public fun initialize(
        dr_account: &signer,
        tc_account: &signer,
    ) {
        DiemTimestamp::assert_genesis();
        // Operational constraint
        CoreAddresses::assert_currency_info(dr_account);
        let (mint_cap, burn_cap) = Diem::register_native_currency<KUSD>(
            dr_account,
            FixedPoint32::create_from_rational(1, 1), // deprecated. exchange rate to PONT
            1000000000000, // scaling_factor = 10^12
            1000000000000, // fractional_part = 10^12
            b"KUSD",
            b"KUSD"
        );

        AccountLimits::publish_unrestricted_limits<KUSD>(dr_account);
        Diem::update_minting_ability<KUSD>(tc_account, false);
        move_to(dr_account, Drop {mint_cap, burn_cap});
    }
}
}
