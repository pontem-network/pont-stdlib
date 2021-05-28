script {
    use 0x1::PONT;
    use 0x1::Pontem;

    fun register_coins() {
        Pontem::register_coin<PONT::T>(b"pont", 18);
    }
}

/// signers: 0x2
/// native_balance: 0x2 pont 100
script {
    use 0x1::PONT;
    use 0x1::Pontem;

    fun main(s: signer) {
        assert(Pontem::get_native_balance<PONT::T>(&s) == 100, 101);

        let ponts = Pontem::deposit_native<PONT::T>(&s, 50);
        assert(Pontem::get_native_balance<PONT::T>(&s) == 50, 102);

        Pontem::withdraw_native(&s, ponts);
        assert(Pontem::get_native_balance<PONT::T>(&s) == 100, 103);
    }
}
