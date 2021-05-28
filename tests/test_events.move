address 0x1 {
module Tokens {
    struct TokenCreatedEvent { val: u128 }

    public(script) fun create_event(val: u128): TokenCreatedEvent {
        TokenCreatedEvent { val }
    }
}
}

script {
    use 0x1::Tokens;
    use 0x1::Event;

    fun main(s: signer) {
        let token_event = Tokens::create_event(10);
        Event::emit(&s, token_event);
    }
}