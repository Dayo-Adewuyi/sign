script {
    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use noncesign_contract::noncesign;

    fun main(account: &signer) {
        noncesign::initialize(account);
    }
}