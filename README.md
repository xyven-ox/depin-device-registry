# DePIN Device Registry

A decentralized registry for DePIN (Decentralized Physical Infrastructure Network) devices built on **BOT Chain** (Chain ID 677) — a high-performance, EVM-compatible Layer 1 blockchain designed for AI Agents, DePIN, and verifiable computing.

## Overview

Device operators register their hardware on-chain, submit data proofs (sensor readings, compute jobs, storage attestations), and earn BOT token rewards for verified contributions. The registry tracks device health via heartbeat monitoring and supports admin moderation.

### Features

- **Register IoT/DePIN devices** on-chain with metadata (model, location, capabilities)
- **5 device types**: Sensor, Compute, Storage, Network, Other
- **Submit data proofs** (keccak256 hashes of sensor readings or compute results)
- **Earn BOT rewards** automatically for each valid submission
- **Heartbeat monitoring** — detect stale/offline devices
- **Device lifecycle management** — activate, deactivate, suspend
- **Admin controls**: adjust fees/rewards, suspend bad actors, pause system, emergency withdraw
- **Reentrancy-safe** via OpenZeppelin's `ReentrancyGuard`

## Quick Start

### Prerequisites

- Node.js 18+
- MetaMask or compatible EVM wallet
- BOT tokens (get test tokens from https://faucet.botchain.ai)

### Install

```bash
npm install
```

### Compile Contracts

```bash
npm run compile
```

### Run Tests

```bash
npm run test
```

### Deploy to BOT Chain

1. Copy `.env.example` to `.env` and add your private key:

```bash
cp .env.example .env
# Edit .env with your wallet private key
```

2. Deploy:

```bash
npm run deploy:botchain
```

3. Update `CONTRACT_ADDRESS` in `frontend/index.html` with the deployed address.

4. Fund the reward pool:

```bash
# In the deploy script, uncomment the fundRewards line, or send BOT manually
```

### Run Frontend

Open `frontend/index.html` in a browser, or serve it:

```bash
npx serve frontend
```

## BOT Chain Network Details

| Item             | Value                        |
|------------------|------------------------------|
| Network Name     | BOT Chain                    |
| RPC URL          | https://rpc.botchain.ai      |
| Chain ID         | 677                          |
| Currency Symbol  | BOT                          |
| Block Explorer   | https://scan.botchain.ai     |

## Contract Architecture

```
DePINRegistry.sol
├── registerDevice()      — Register a new device (pays registration fee)
├── updateDevice()        — Update device metadata
├── deactivateDevice()    — Owner deactivates their device
├── reactivateDevice()    — Owner reactivates their device
├── submitData()          — Submit a data proof hash + receive BOT reward
├── getOwnerDevices()     — List all devices for an address
├── getDevice()           — Get full device details
├── isDeviceStale()       — Check if device missed heartbeat
├── suspendDevice()       — Admin suspends a bad-acting device
├── setRegistrationFee()  — Admin updates the registration cost
├── setRewardPerSubmission() — Admin updates reward per data submission
├── fundRewards()         — Admin deposits BOT for rewards
└── pause/unpause()       — Emergency controls
```

## How It Works

1. **Device operator** registers their hardware by calling `registerDevice()` with a unique device ID, metadata JSON, and the registration fee in BOT.
2. The device periodically **submits data proofs** — hashes of real-world data (sensor readings, compute proofs, etc.) — via `submitData()`.
3. Each valid submission **earns BOT rewards** sent directly to the operator's wallet.
4. The contract monitors **heartbeat intervals** — if a device stops submitting, it's flagged as stale.
5. **Admins** can suspend abusive devices and adjust economic parameters.

## Security

- Built with OpenZeppelin `ReentrancyGuard`, `Ownable`, and `Pausable`
- BOT Chain core contracts are audited by CertiK: https://skynet.certik.com/projects/botchain

## Resources

- BOT Chain Website: https://www.botchain.ai
- Developer Docs: https://dev-docs.botchain.ai/docs/Developers/quick-guide/
- Block Explorer: https://scan.botchain.ai
- Testnet Faucet: https://faucet.botchain.ai
- GitHub: https://github.com/BOTChain-bot

## License

MIT
