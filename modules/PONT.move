address 0x1 {

/// PONT Coin. The one and only.
/// Put into separate module to highlight its importance and role in Pontem
/// ecosystem. Also moved not to be mistaken for peg-zone coin. Same-naming
/// attack from peg-zone is impossible when XFI coin moved outside of Coins module
module PONT {
    use 0x1::AccountLimits;
    use 0x1::CoreAddresses;
    use 0x1::FixedPoint32;
    use 0x1::Diem;
    use 0x1::DiemTimestamp;

    struct PONT has key, store {}

    struct Drop has key {
        mint_cap: Diem::MintCapability<PONT>,
        burn_cap: Diem::BurnCapability<PONT>,
    }

    /// Registers the `XUS` cointype. This can only be called from genesis.
    public fun initialize(
        dr_account: &signer,
        tc_account: &signer,
    ) {
        DiemTimestamp::assert_genesis();
        // Operational constraint
        CoreAddresses::assert_currency_info(dr_account);
        let (mint_cap, burn_cap) = Diem::register_native_currency<PONT>(
            dr_account,
            FixedPoint32::create_from_rational(1, 1), // exchange rate to XDX TODO?!
            1000000, // scaling_factor = 10^6
            100,     // fractional_part = 10^2
            b"PONT",
            b"PONT"
        );

        AccountLimits::publish_unrestricted_limits<PONT>(dr_account);
        Diem::update_minting_ability<PONT>(tc_account, false);
        move_to(dr_account, Drop {mint_cap, burn_cap});
    }
}
}
