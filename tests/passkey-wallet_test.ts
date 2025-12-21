import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Can register a new passkey",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            Tx.contractCall(
                'passkey-registry',
                'register-passkey',
                [
                    types.buff(new Uint8Array(65).fill(1)), // passkey-id
                    types.ascii("iPhone-FaceID")              // device-type
                ],
                user1.address
            )
        ]);

        block.receipts[0].result.expectOk().expectBool(true);

        // Verify passkey was registered
        let checkBlock = chain.mineBlock([
            Tx.contractCall(
                'passkey-registry',
                'is-passkey-registered',
                [
                    types.principal(user1.address),
                    types.buff(new Uint8Array(65).fill(1))
                ],
                user1.address
            )
        ]);

        checkBlock.receipts[0].result.expectBool(true);
    },
});

Clarinet.test({
    name: "Can initialize wallet with multi-sig threshold",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            Tx.contractCall(
                'wallet-core',
                'initialize-wallet',
                [types.uint(2)], // 2-of-N threshold
                user1.address
            )
        ]);

        block.receipts[0].result.expectOk().expectBool(true);
    },
});

Clarinet.test({
    name: "Can add and verify guardian",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        const guardian = accounts.get('wallet_2')!;

        let block = chain.mineBlock([
            Tx.contractCall(
                'recovery-guardian',
                'add-guardian',
                [types.principal(guardian.address)],
                user1.address
            )
        ]);

        block.receipts[0].result.expectOk().expectBool(true);

        // Verify guardian was added
        let checkBlock = chain.mineBlock([
            Tx.contractCall(
                'recovery-guardian',
                'is-guardian',
                [
                    types.principal(user1.address),
                    types.principal(guardian.address)
                ],
                user1.address
            )
        ]);

        checkBlock.receipts[0].result.expectOk().expectBool(true);
    },
});

Clarinet.test({
    name: "Can register device with permissions",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;

        // First register a passkey
        let passkeyBlock = chain.mineBlock([
            Tx.contractCall(
                'passkey-registry',
                'register-passkey',
                [
                    types.buff(new Uint8Array(65).fill(1)),
                    types.ascii("MacBook-TouchID")
                ],
                user1.address
            )
        ]);

        // Register device
        let deviceBlock = chain.mineBlock([
            Tx.contractCall(
                'device-manager',
                'register-device',
                [
                    types.buff(new Uint8Array(65).fill(2)),   // device-id
                    types.buff(new Uint8Array(65).fill(1)),   // passkey-id
                    types.ascii("MacBook Pro"),                // device-name
                    types.ascii("sign")                        // permission-level
                ],
                user1.address
            )
        ]);

        deviceBlock.receipts[0].result.expectOk().expectBool(true);
    },
});
