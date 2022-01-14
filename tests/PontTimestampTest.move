#[test_only]
module PontemFramework::PontTimestampTest {
    use PontemFramework::PontTimestamp;
    use PontemFramework::Genesis;

    #[test(root_acc = @Root)]
    fun test_time_on_genesis(root_acc: signer) {
        Genesis::setup(&root_acc, 1);

        assert!(PontTimestamp::now_microseconds() == 0, 1);
        assert!(PontTimestamp::now_seconds() == 0, 1);
    }

    #[test(root_acc = @Root)]
    fun test_set_custom_time_microseconds(root_acc: signer) {
        Genesis::setup(&root_acc, 1);

        PontTimestamp::set_time_microseconds(100);
        assert!(PontTimestamp::now_microseconds() == 100, 1);
        assert!(PontTimestamp::now_seconds() == 0, 2);

        PontTimestamp::set_time_microseconds(1000000);
        assert!(PontTimestamp::now_microseconds() == 1000000, 3);
        assert!(PontTimestamp::now_seconds() == 1, 4);
    }

    #[test(root_acc = @Root)]
    fun test_set_custom_time_seconds(root_acc: signer) {
        Genesis::setup(&root_acc, 1);

        PontTimestamp::set_time_seconds(2);
        assert!(PontTimestamp::now_microseconds() == 2000000, 1);
        assert!(PontTimestamp::now_seconds() == 2, 2);
    }
}
