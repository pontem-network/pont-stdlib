address 0x1 {
module SecurityStorage {

    use 0x1::Security::{Security};
    use 0x1::Vector;
    use 0x1::Signer;

    resource struct T<For: copyable> {
        securities: vector<Security<For>>
    }

    public fun init<For: copyable>(account: &signer) {
        move_to<T<For>>(account, T {
            securities: Vector::empty<Security<For>>()
        });
    }

    public fun push<For: copyable>(
        account: &signer,
        security: Security<For>
    ) acquires T {
        Vector::push_back(
            &mut borrow_global_mut<T<For>>(Signer::address_of(account)).securities
            , security
        );
    }

    public fun take<For: copyable>(
        account: &signer,
        el: u64
    ): Security<For> acquires T {
        let me  = Signer::address_of(account);
        let vec = &mut borrow_global_mut<T<For>>(me).securities;

        Vector::remove(vec, el)
    }
}
}
