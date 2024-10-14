script {
    use std::signer;
    use noncesign_contract::noncesign;

    fun init_noncesign(account: signer) {
        let account_addr = signer::address_of(&account);
        
       
        if (!noncesign::is_initialized(account_addr)) {
            noncesign::initialize(&account);
        };
    }
}