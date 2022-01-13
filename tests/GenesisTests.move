module PontemFramework::GenesisTests {
    use PontemFramework::Genesis;
    use PontemFramework::Token;
    use PontemFramework::KSM::KSM;
    use PontemFramework::PONT::PONT;

    #[test(acc = @0x1234)]
    fun test_genesis_cannot_be_started_with_any_other_account(acc: signer) {
        Genesis::setup(&acc, 1);
    }

    // TODO: change into proper abort_code
    #[test(root_acc = @Root)]
    #[expected_failure(abort_code = 1)]
    fun test_genesis_cannot_be_run_twice(root_acc: signer) {
        Genesis::setup(&root_acc, 1);
        Genesis::setup(&root_acc, 1);
    }

    #[test(root_acc = @Root)]
    fun test_run_genesis(root_acc: signer) {
        Genesis::setup(&root_acc, 1);

        Token::assert_is_token<KSM>();
        Token::assert_is_token<PONT>();
    }
}