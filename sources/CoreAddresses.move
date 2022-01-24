/// Module providing well-known addresses and related logic.
module PontemFramework::CoreAddresses {
    use Std::Errors;
    use Std::Signer;

    /// The operation can only be performed by the account at 0xA550C18 (Root)
    const ERR_ROOT: u64 = 0;

    /// Assert that the account is the  Root address.
    public fun assert_root(account: &signer) {
        assert!(
            Signer::address_of(account) == @Root,
            Errors::requires_address(ERR_ROOT))
    }
    spec assert_root {
        pragma opaque;
        include AbortsIfNotRoot{ account };
    }

    /// Specifies that a function aborts if the account does not have the Diem root address.
    spec schema AbortsIfNotRoot {
        account: signer;
        aborts_if Signer::address_of(account) != @Root with Errors::REQUIRES_ADDRESS;
    }
}
