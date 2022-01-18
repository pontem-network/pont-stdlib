#[test_only]
module PontemFramework::ChainIdTests {
    use PontemFramework::ChainId;
    use PontemFramework::Genesis;

    #[test(root_acc = @Root)]
    fun test_chain_id_initialized_on_genesis(root_acc: signer) {
        Genesis::setup(&root_acc, 1);

        assert!(ChainId::get() == 1, 1);
    }
}
