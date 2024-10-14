module noncesign_contract::noncesign {
    use std::string::{String, utf8};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

    // Document, Signature, and Event Structures
    struct Document has store {
        id: u64,
        title: String,
        description: String,
        file_hash: String,
        final_hash: String,
        signers: vector<address>,
        creator: address,
        completed: bool,
    }

    struct Signature has store {
        signer: address,
        signature_hash: String,
        timestamp: u64,
    }

    struct NonceSignState has key {
        documents: Table<u64, Document>,
        document_signatures: Table<u64, vector<Signature>>,
        document_count: u64,
        owner: address,
        user_created_documents: Table<address, vector<u64>>,
        user_signed_documents: Table<address, vector<u64>>,
        document_created_events: EventHandle<DocumentCreatedEvent>,
        document_signed_events: EventHandle<DocumentSignedEvent>,
        document_completed_events: EventHandle<DocumentCompletedEvent>,
        ownership_transferred_events: EventHandle<OwnershipTransferredEvent>,
    }

    // Events
    struct DocumentCreatedEvent has drop, store {
        document_id: u64,
        title: String,
        signers: vector<address>,
        creator: address,
    }

    struct DocumentSignedEvent has drop, store {
        document_id: u64,
        signer: address,
        signature_hash: String,
    }

    struct DocumentCompletedEvent has drop, store {
        document_id: u64,
        final_hash: String,
    }

    struct OwnershipTransferredEvent has drop, store {
        previous_owner: address,
        new_owner: address,
    }

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_DOCUMENT_COMPLETED: u64 = 2;
    const E_ALREADY_SIGNED: u64 = 3;
    const E_INVALID_INPUT: u64 = 4;
    const E_DOCUMENT_NOT_FOUND: u64 = 5;
    const E_ALREADY_INITIALIZED: u64 = 6;
    const E_DOCUMENT_COUNT_OVERFLOW: u64 = 7;

    // Initialization
   public entry fun initialize(account: &signer) {
        let sender = account::get_signer_address(account);
        assert!(!exists<NonceSignState>(sender), E_ALREADY_INITIALIZED);
        move_to(account, NonceSignState {
            documents: table::new(),
            document_signatures: table::new(),
            document_count: 0,
            owner: sender,
            user_created_documents: table::new(),
            user_signed_documents: table::new(),
            document_created_events: account::new_event_handle<DocumentCreatedEvent>(account),
            document_signed_events: account::new_event_handle<DocumentSignedEvent>(account),
            document_completed_events: account::new_event_handle<DocumentCompletedEvent>(account),
            ownership_transferred_events: account::new_event_handle<OwnershipTransferredEvent>(account),
        });
    }

   // Document Creation
public entry fun create_document(
    account: &signer,
    title: String,
    description: String,
    file_hash: String,
    signers: vector<address>
) acquires NonceSignState {
    let sender = account::get_signer_address(account);
    let state = borrow_global_mut<NonceSignState>(sender);
    
    // Validate input fields
    assert!(!vector::is_empty(&signers), E_INVALID_INPUT);
    assert!(!string::is_empty(&title), E_INVALID_INPUT);
    assert!(!string::is_empty(&file_hash), E_INVALID_INPUT);

    // Generate document ID and handle overflow
    let document_id = state.document_count;
    assert!(document_id < u64::MAX, E_DOCUMENT_COUNT_OVERFLOW);
    state.document_count = document_id + 1;

    // Create the new document
    let new_doc = Document {
        id: document_id,
        title,
        description,
        file_hash,
        final_hash: String::from_utf8(vector::empty<u8>()),
        signers,
        creator: sender,
        completed: false,
    };

    // Add document to the documents table
    table::add(&mut state.documents, document_id, new_doc);

    // Record the document ID for the creator
    if (!table::contains(&state.user_created_documents, sender)) {
        table::add(&mut state.user_created_documents, sender, vector::empty());
    };
    vector::push_back(table::borrow_mut(&mut state.user_created_documents, sender), document_id);

    // Emit a DocumentCreated event
    event::emit_event(&mut state.document_created_events, DocumentCreatedEvent {
        document_id,
        title,
        signers,
        creator: sender,
    });
}

// Document Signing
public entry fun sign_document(
    account: &signer,
    document_id: u64,
    signature_hash: String
) acquires NonceSignState {
    let sender = account::get_signer_address(account);
    let state = borrow_global_mut<NonceSignState>(sender);
    
    // Verify document existence and validity
    assert!(table::contains(&state.documents, document_id), E_DOCUMENT_NOT_FOUND);
    let doc = table::borrow_mut(&mut state.documents, document_id);
    
    assert!(!doc.completed, E_DOCUMENT_COMPLETED);
    assert!(is_authorized_signer(sender, &doc.signers), E_NOT_AUTHORIZED);
    assert!(!has_signer_signed(state, document_id, sender), E_ALREADY_SIGNED);
    assert!(!string::is_empty(&signature_hash), E_INVALID_INPUT);

    // Create and add the new signature
    let new_signature = Signature {
        signer: sender,
        signature_hash: signature_hash.clone(),
        timestamp: timestamp::now_seconds(),
    };

    if (!table::contains(&state.document_signatures, document_id)) {
        table::add(&mut state.document_signatures, document_id, vector::empty());
    };
    vector::push_back(table::borrow_mut(&mut state.document_signatures, document_id), new_signature);

    if (!table::contains(&state.user_signed_documents, sender)) {
        table::add(&mut state.user_signed_documents, sender, vector::empty());
    };
    vector::push_back(table::borrow_mut(&mut state.user_signed_documents, sender), document_id);

    // Emit a DocumentSigned event
    event::emit_event(&mut state.document_signed_events, DocumentSignedEvent {
        document_id,
        signer: sender,
        signature_hash: signature_hash.clone(),
    });

    // Check if all required signers have signed
    if (all_signed(state, document_id)) {
        doc.completed = true;
        doc.final_hash = signature_hash;
        event::emit_event(&mut state.document_completed_events, DocumentCompletedEvent { 
            document_id,
            final_hash: signature_hash,
        });
    };
}


  // Helper functions

  fun is_authorized_signer(signer: address, signers: &vector<address>): bool {
        vector::contains(signers, &signer)
    }

    public fun get_final_hash(state: &NonceSignState, document_id: u64): String {
        assert!(table::contains(&state.documents, document_id), E_DOCUMENT_NOT_FOUND);
        let doc = table::borrow(&state.documents, document_id);
        assert!(doc.completed, E_DOCUMENT_COMPLETED);
        doc.final_hash
    }

// Checks if the signer has already signed the document
fun has_signer_signed(state: &NonceSignState, document_id: u64, signer: address): bool {
    if (!table::contains(&state.document_signatures, document_id)) {
        return false;
    };
    let signatures = table::borrow(&state.document_signatures, document_id);
    vector::any(signatures, |s: &Signature| s.signer == signer)
}

// Checks if all signers for a document have signed
fun all_signed(state: &NonceSignState, document_id: u64): bool {
    let doc = table::borrow(&state.documents, document_id);
    let signers = &doc.signers;
    vector::all(signers, |signer: &address| has_signer_signed(state, document_id, *signer))
}


 
  // Query Functions
  #[view]
 public fun get_documents_created_by_user(state: &NonceSignState, user: address): vector<Document> {
        if (!table::contains(&state.user_created_documents, user)) {
            return vector::empty();
        };
        let user_docs = table::borrow(&state.user_created_documents, user);
        vector::map(user_docs, |doc_id| *table::borrow(&state.documents, *doc_id))
    }
  #[view]
 public fun get_documents_assigned_to_user_for_signing(state: &NonceSignState, user: address): vector<Document> {
        let result = vector::empty<Document>();
        let i = 0;
        while (i < state.document_count) {
            if (table::contains(&state.documents, i)) {
                let doc = table::borrow(&state.documents, i);
                if (is_authorized_signer(user, &doc.signers) && !doc.completed) {
                    vector::push_back(&mut result, *doc);
                };
            };
            i = i + 1;
        };
        result
    }

    #[view]
    public fun get_document(state: &NonceSignState, document_id: u64): Document {
        assert!(table::contains(&state.documents, document_id), E_DOCUMENT_NOT_FOUND);
        *table::borrow(&state.documents, document_id)
    }

    #[view]
    public fun get_document_signatures(state: &NonceSignState, document_id: u64): vector<Signature> {
        assert!(table::contains(&state.document_signatures, document_id), E_DOCUMENT_NOT_FOUND);
        *table::borrow(&state.document_signatures, document_id)
    }

// Access control
public fun assert_owner(state: &NonceSignState, account: &signer) {
    assert!(account::get_signer_address(account) == state.owner, E_NOT_AUTHORIZED);
}

// Contract management
public entry fun transfer_ownership(account: &signer, new_owner: address) acquires NonceSignState {
    let state = borrow_global_mut<NonceSignState>(account::get_signer_address(account));
    assert_owner(state, account);
    assert!(state.owner != new_owner, E_NOT_AUTHORIZED); 
    let previous_owner = state.owner;
    state.owner = new_owner;
    event::emit_event(&mut state.ownership_transferred_events, OwnershipTransferredEvent {
        previous_owner,
        new_owner,
    });
}


public entry fun update_document(
    account: &signer,
    document_id: u64,
    new_title: String,
    new_description: String
) acquires NonceSignState {
    let state = borrow_global_mut<NonceSignState>(account::get_signer_address(account));
    assert!(table::contains(&state.documents, document_id), E_DOCUMENT_NOT_FOUND);
    let doc = table::borrow_mut(&mut state.documents, document_id);
    assert!(account::get_signer_address(account) == doc.creator, E_NOT_AUTHORIZED);
    assert!(!doc.completed, E_DOCUMENT_COMPLETED);
    assert!(!table::contains(&state.document_signatures, document_id) || 
            vector::is_empty(table::borrow(&state.document_signatures, document_id)), E_NOT_AUTHORIZED);

    assert!(!string::is_empty(&new_title), E_INVALID_INPUT);
    doc.title = new_title;
    doc.description = new_description;
}

}