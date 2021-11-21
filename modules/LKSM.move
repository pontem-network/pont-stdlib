address 0x1 {

/// LKSM (Liquid Kusama, from Karura network) Coin.
module LKSM {
    use 0x1::AccountLimits;
    use 0x1::CoreAddresses;
    use 0x1::FixedPoint32;
    use 0x1::Diem;
    use 0x1::DiemTimestamp;

    struct LKSM has key, store {}

    struct Drop has key {
        mint_cap: Diem::MintCapability<LKSM>,
        burn_cap: Diem::BurnCapability<LKSM>,
    }

    /// Registers the `KSM` cointype. This can only be called from genesis.
    public fun initialize(
        dr_account: &signer,
        tc_account: &signer,
    ) {
        DiemTimestamp::assert_genesis();
        // Operational constraint
        CoreAddresses::assert_currency_info(dr_account);
        let (mint_cap, burn_cap) = Diem::register_native_currency<LKSM>(
            dr_account,
            FixedPoint32::create_from_rational(1, 1), // deprecated. exchange rate to PONT
            1000000000000, // scaling_factor = 10^12
            1000000000000, // fractional_part = 10^12
            b"LKSM",
            b"LKSM"
        );

        AccountLimits::publish_unrestricted_limits<LKSM>(dr_account);
        Diem::update_minting_ability<LKSM>(tc_account, false);
        move_to(dr_account, Drop {mint_cap, burn_cap});
    }
}
}
