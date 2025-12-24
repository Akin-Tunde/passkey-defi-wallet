import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

// Get account addresses from the simnet
const accounts = simnet.getAccounts();
const user1 = accounts.get("wallet_1")!;
const user2 = accounts.get("wallet_2")!;

describe("Passkey-Based DeFi Wallet Test Suite", () => {
  
  it("Can register a new passkey", () => {
    const passkeyId = Cl.buffer(new Uint8Array(65).fill(1));
    const deviceType = Cl.stringAscii("iPhone-FaceID"); // Fixed: changed .ascii to .stringAscii

    // Call register-passkey
    const response = simnet.callPublicFn(
      "passkey-registry",
      "register-passkey",
      [passkeyId, deviceType],
      user1
    );

    // Assert successful registration
    expect(response.result).toBeOk(Cl.bool(true));

    // Verify via read-only function
    const check = simnet.callReadOnlyFn(
      "passkey-registry",
      "is-passkey-registered",
      [Cl.principal(user1), passkeyId],
      user1
    );
    
    expect(check.result).toBeBool(true);
  });

  it("Can initialize wallet with multi-sig threshold", () => {
    const threshold = Cl.uint(2); // 2-of-N

    const response = simnet.callPublicFn(
      "wallet-core",
      "initialize-wallet",
      [threshold],
      user1
    );

    expect(response.result).toBeOk(Cl.bool(true));
  });

  it("Can add and verify guardian", () => {
    const response = simnet.callPublicFn(
      "recovery-guardian",
      "add-guardian",
      [Cl.principal(user2)],
      user1
    );

    expect(response.result).toBeOk(Cl.bool(true));

    // Verify guardian status
    const check = simnet.callReadOnlyFn(
      "recovery-guardian",
      "is-guardian",
      [Cl.principal(user1), Cl.principal(user2)],
      user1
    );

    expect(check.result).toBeOk(Cl.bool(true));
  });

  it("Can register device with permissions", () => {
    const deviceId = Cl.buffer(new Uint8Array(65).fill(2));
    const passkeyId = Cl.buffer(new Uint8Array(65).fill(1));
    const deviceName = Cl.stringAscii("MacBook Pro"); // Fixed: changed .ascii to .stringAscii
    const permission = Cl.stringAscii("sign");       // Fixed: changed .ascii to .stringAscii

    // Ensure a passkey is registered first for this user
    simnet.callPublicFn(
      "passkey-registry",
      "register-passkey",
      [passkeyId, Cl.stringAscii("MacBook-TouchID")],
      user1
    );

    const response = simnet.callPublicFn(
      "device-manager",
      "register-device",
      [deviceId, passkeyId, deviceName, permission],
      user1
    );

    expect(response.result).toBeOk(Cl.bool(true));
  });

});