# AnomaPay ERC20 Forwarder - Incident Response Plan

 **PUBLIC VERSION**
 
## Confidentiality Notice

This document contains sensitive operational procedures. Share only with team members who have a direct role in incident response.

---

## Who to Contact

When an incident occurs, gather the right people immediately.

**War Room Slack Channels:** 

| Role | Channel |
|------|------|
| Protocol Adapter Team | `#protocol-adapter` |
| Past Auditor(s) | `#collab-informal-systems` |
| RISC Zero | `#collab-risczero` |
| Frontend/Backend Team | `#anomapay` |

---

## Contract Addresses

| Contract | Address |
|----------|---------|
| Token | *[Address]* |
| ERC20Forwarder | *[Address]* |
| ERC20Forwarder Emergency Committee | `0xc703402252Ce1251aa07e0815D50060d27fdd6C4` |
| ProtocolAdapter | *[Address]* |
| ProtocolAdapter Emergency Committee | `0xE9082Ac8Aa2Fb27DEfDBAC604921C196b884Da10` |

---

## Incident Scenarios

### Scenario A: We Detect an Active Exploit (PA and ERC20Forwarder are compromised)

Follow the steps in **Immediate Response** below.

### Scenario B: RISC Zero Notifies Us of a Vulnerability

When RISC Zero identifies a vulnerability and notifies us proactively (via Slack):

1. **Decide on emergency stop timing** - Coordinate with RISC Zero on Slack on when to trigger the stop if immediate action is required
2. **Prepare recovery infrastructure** - Have the Emergency Committee ready to act
3. **If immediate action required:** - Proceed directly to **Take Defensive Action**

---

## Immediate Response

### 1. Coordinate with the AnomaPay team to disable the Frontend

**Do this first.** Prevent users from interacting with potentially compromised contracts while you investigate.

**Frontend:** https://anomapay.app/

This buys you time to investigate without users continuing to deposit funds into a vulnerable system.

---

### 2. Understand What Happened

Before making irreversible decisions, remember that once contracts are compromised, they are permanently halted, 
so it's essential to identify the root cause first. Rushing to "fix" issues without understanding the underlying
problem can lead to further complications.

- [ ] **Identify the vulnerability**

**Investigation tools:**
- [Etherscan](https://etherscan.io/) - Token balance page
- [Tenderly Debugger](https://dashboard.tenderly.co/) - Step-through debugging
- Foundry's `cast run` for local transaction replay

**Key diagnostic queries:**

| What to check | Contract | Function | Called by |
|---------------|----------|----------|-----------|
| Forwarder token balance | Token | `balanceOf(address)` | Anyone |
| Current emergency caller | ERC20Forwarder | `getEmergencyCaller()` | Anyone |
| Protocol Adapter status | ProtocolAdapter | `isEmergencyStopped()` | Anyone |

---

### 3. Take Defensive Action

> **CRITICAL: IRREVERSIBLE ACTIONS**
>
> | Action | Contract | Who can call | Reversible? |
> |--------|----------|--------------|-------------|
> | `setEmergencyCaller(address)` | ERC20Forwarder | Emergency Committee | **NO** - one-time only |
> | Emergency stop | ProtocolAdapter | Emergency Committee | **NO** - permanent |
>
> Once the Protocol Adapter is stopped, **normal operations will never resume** on these contracts. Recovery means
> deploying new contracts and migrating funds.

#### Step 3a: Stop the Protocol Adapter

The Emergency Committee can stop the Protocol Adapter by calling the `emergencyStop()` function on the ProtocolAdapter.

Verify the Protocol Adapter is stopped by calling the `isEmergencyStopped()` function on the ProtocolAdapter.

Verify the Emergency Committee can set the emergency caller by calling the `getEmergencyCaller()` function on the ERC20Forwarder.

Possible errors:

| Error | Meaning |
|-------|---------|
| `EmergencyCallerNotSet()` | Step 3b was not completed |
| `ProtocolAdapterNotStopped()` | Step 3a was not completed |
| `UnauthorizedCaller(expected, actual)` | Caller is not the designated emergency caller |
| `BalanceMismatch(expected, actual)` | Token has transfer fees; adjust amount |

---

### 4. Contact Security Partners

- [ ] **Notify past auditors** (via Slack `#collab-informal-systems`)

Keep the circle of trust small. If funds were stolen, contact law enforcement and asset recovery specialists immediately.

---

### 6. Notify Users

- [ ] **Post to Discord**
- [ ] **Post to Anoma Slack**
- [ ] **Post to Twitter/X**
- [ ] **Update the status page**

Guidelines:

- Update at least every 24 hours
- Have someone review every message before posting
- Do not share technical details that could help copycats

---

## Recovery Phase

### 7. Write the Postmortem

- [ ] **Draft a full public postmortem**
Include: timeline, root cause, impact, remediation, and prevention measures.

---

### 8. Deploy New Contracts and Migrate Users

The emergency stop is permanent. Resuming service requires new contract deployments
and may take time, possibly days.

- [ ] **Deploy new Protocol Adapter (V2)**
- [ ] **Deploy new ERC20ForwarderV2**
- [ ] **Get auditor review**
- [ ] **Migrate user funds from V1 to V2**

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | *[Date]* | *[Author]* | Initial version |
